---
title: "Call Me Maybe?"
date: 2024-06-23T23:16:51+01:00
draft: true
tags: go, distributed-systems
---

What I learned [solving](https://github.com/hailelagi/gossip-glomers) the [fly.io distributed systems challenges](https://www.fly.io/dist-sys).

The title of this post is inspired by [kyle kingsbury' series of articles like this one](https://aphyr.com/posts/316-call-me-maybe-etcd-and-consul) and [this one](https://aphyr.com/posts/315-call-me-maybe-rabbitmq) and of course:

{{< spotify type="track" id="20I6sIOMTCkB6w7ryavxtO" >}}

{{< toc >}}

## 1. Echo
saying hello world! but distributed systems style, it's mostly boilerplate setup, 
reading the maelstrom docs and the go client docs, we instantiate a maelstrom node/binary, define an RPC style handler and return messages:

```go
func main() {
	n := maelstrom.NewNode()

	// Register a handler for the "echo" message that responds with an "echo_ok".
	n.Handle("echo", func(msg maelstrom.Message) error {
		// Unmarshal the message body as an loosely-typed map.
		var body map[string]any
		if err := json.Unmarshal(msg.Body, &body); err != nil {
			return err
		}

		// Update the message type.
		body["type"] = "echo_ok"

		// Echo the original message back with the updated message type.
		return n.Reply(msg, body)
	})

	// Execute the node's message loop. This will run until STDIN is closed.
	if err := n.Run(); err != nil {
		log.Printf("ERROR: %s", err)
		os.Exit(1)
	}
}
```


## 2. Unique ID Generation

In a single node/computer, generation of unique ids is typically achieved using a growing monontonic sequence such as a counter or the system clock.

In the view of a distributed system where each node could increment this counter simultaneously and the [the system clock is unreliable](https://tigerbeetle.com/blog/three-clocks-are-better-than-one) there needs to be some way of solving this [global clock synchronisation problem](https://www.youtube.com/watch?v=mAyW-4LeXZo) of not only skewing different "times" but logical ordering of events. What to do? We also want to prevent the need to exchange messages or co-ordination so lamport clocks are out!

1. A pseudo logical event clock where we can represent causal dependencies as combinations of properties of our system for e.g the system clock + orignating node id + a random request id(tie breaker). Luckily for this challenge there aren't requirements for **space** or **ordering** or **causality**, only **global uniqueness**, which is naive but isn't too far off more sophisticated schemes [^1] [^2] [^3]

```go
func genNaive(nodeID string) int64 {
	requestID := strconv.FormatInt(rand.Int63n(100), 10)
	sequenceId := strconv.FormatInt(time.Now().UnixMicro(), 10)
	originId := nodeID[1:]

	identity := originId + requestID + sequenceId

	if id, err := strconv.ParseInt(identity, 10, 64); err != nil {
		log.Fatal(err)
		return 0
	} else {
		return id
	}
}
```

2. hash a seed over a really large key space (2**128 - 1) - a uuid.

3. The use of a central authority, such as an atomic clock + GPS and/or other clever distributed algorithms[^4] provided by a [time server(s)](https://cloud.google.com/spanner/docs/true-time-external-consistency).

## 3. Broadcast

Our first "official" distributed algorithm! a way to gossip information to nodes. Incrementally we scaffold basic messaging,
sending data efficiently, simulating network partitions, variable latencies and interesting node topologies!

We keep all data we've seen in-memory in a simple "store":
```go
type store struct {
	index map[float64]bool
	log   []float64
	sync.RWMutex
}

// a session is a wrapper instance of a maelstrom node
// that can read/write from a single store and `handle` messages
type session struct {
	node    *maelstrom.Node
	store   *store
	retries chan retry
}
```

reading, we simply take a `read` lock, respond with what's in our `log` so far.

If we get a `broadcast` message we concurrently attempt to send it to all our neighbours,  excluding ourself, store it in `log` and `index` so we can test if we've seen this message before and short circuit duplicate broadcast replies:
```go
// spam everyone in this network we know of, and so on...
for _, dest := range n.NodeIDs() {
	if dest == n.ID() {
		continue
	}

	wg.Add(1)
	
	go func(dest string) {
		deadline := time.Now().Add(400*time.Millisecond)
		bgd := context.Background()
		ctx, cancel := context.WithDeadline(bgd, deadline)
		defer cancel()
		defer wg.Done()

		_, err := n.SyncRPC(ctx, dest, body)

		if err == nil {
			return
		} else {
			// failure detection up next!
		}
	}(dest)
}

wg.Wait()
```

Our failure detection algorithm is a simple FIFO queue using go's channels, for the un-initiated in go-ism, it's conceputally an ["atomic circular buffer"](https://cs.opensource.google/go/go/+/refs/tags/go1.22.3:src/runtime/chan.go;l=33), if that doesn't mean much --  it's a 'concurrent safe queue', so we can handle network partitions and variable latency async! 
We send messages into a buffered channel, in our else block and read it (if/when) we have to retry in a seperate goroutine(s):
```
s.retries <- Retry{body: body, dest: dest, attempt: 20, err: err}
```

we guess-timate a queue size (I'm not 100% about this bit lmk if I'm wrong!):
```go
/*
 little's law: L (num units) = arrival rate * wait time
 rate == 100 msgs/sec assuming efficient workload,
 latency/wait mininum = 100ms, 400ms average

 100 * 0.4 = 40 msgs per request * 25 - 1(self) nodes 

 = 960 queue size, will use ~1000
*/
var retries = make(chan retry, 1000)

```

The spurious errors and on/off successes and failures making this were... interesting to debug! non-deterministic systems are... something.
Anyway, a few `failureDetector` go routines are spawned and sleep until messages are in the queue. 
```go
	for i := 0; i < runtime.NumCPU(); i++ {
		go failureDetector(s)
	}
```
What suprised me was the tweaking of the `deadline` a longer deadline would lead to consistently more reliable delivery vs retrying in smaller intervals -- this should have been obvious, but I only understood this in hindsight.

> there’s always a trade-off between wrongly suspecting alive processes as dead (producing false-positives), and delaying marking an unresponsive process as dead, giving it the benefit of doubt and expecting it to respond eventually (producing false-negatives).

Which is to say a shorter deadline can make a more _efficient_ algorithm with lower latency, but it's less _accurate_ and detects down nodes less reliably leading to more retry storms and eventually possibly overwhelming the partial async timing model assumptions.

```go
// a naive failure detector :)
func failureDetector(s *session) {
    var atttempts sync.WaitGroup

    for r := range s.retries {
	  r := r
	  atttempts.Add(1)

	  go func(retry retry, attempts *sync.WaitGroup) {
		  deadline := time.Now().Add(800 * time.Millisecond)
		  ctx, cancel := context.WithDeadline(context.Background(), deadline)
		  defer cancel()
		  defer attempts.Done()

		  retry.attempt--

		  if retry.attempt >= 0 {
			  _, err := s.node.SyncRPC(ctx, retry.dest, retry.body)

			  if err == nil {
				  return
			  }
			  s.retries <- retry

		  } else {
			  log.SetOutput(os.Stderr)
			  log.Printf("dead letter message slip loss beyond tolerance %v", retry)
			}
		}(r, &atttempts)
	}
	
	atttempts.Wait()
}
```

> A perfect timeout-based failure detector exists only in a synchronous crash-stop system with reliable
links; in a partially synchronous system, a perfect failure detector does not exist
>
> -- https://www.cl.cam.ac.uk/teaching/2122/ConcDisSys/dist-sys-notes.pdf


and finally we optimise! we're sending far too many messages and flooding the entire network! even if it's impossible to be both accurate and fast, we try anyway -- gotta get those p99s up! there's a hint about network topology so let's re-examine that:
```go
var neighbors []any

func (s *session) topologyHandler(msg maelstrom.Message) error {
	var body = make(map[string]any)

	if err := json.Unmarshal(msg.Body, &body); err != nil {
		return err
	}

	self := s.node.ID()
	topology := body["topology"].(map[string]any)
	neighbors = topology[self].([]any)

	return s.node.Reply(msg, map[string]any{"type": "topology_ok"})
}
```

For this bit, I had to draw up the messsaging flow of the network topology on pen and paper. First I tried to send only to immediately connected neighbours. For example in a 5 node cluster of `a, b, c, d, e` a would neighbour  `b, c` and so on forming a grid:

This is `O(n) * sqrt(n)`:

```
a ++ b ++ d
+    +    +
c ++ e  /
```

instead of `a` spamming `b`, `c`, `d` and `e` and so on which is `O(n)^2`

```diff
-- // spam everyone in this network we know of, and so on...
-- for _, dest := range n.NodeIDs()
++ // send to our "overlay" neighbors only
++ for _, dest := range neighbors
```

[Database Internals chapter 12](https://learning.oreilly.com/library/view/database-internals/9781492040330/ch12.html) and the [maelstrom docs](https://github.com/jepsen-io/maelstrom/blob/main/doc/03-broadcast/02-performance.md) were also super helpful on where to go about exploring options, network topologies for broadcast are a deep topic, so we'll only review a very tiny subset we're interested in:
1. a fully connected grid mesh (what we had before) [to quote wikipedia](https://en.wikipedia.org/wiki/Network_topology):
>  Networks designed with this topology are usually very expensive to set up, but provide a high degree of reliability due to the multiple paths for data that are provided by the large number of redundant links between nodes

{{% callout color="#ffd700" %}}
distributed erlang nodes deliver rpc messages as a <a href="https://www.erlang.org/doc/system/distributed.html#node-connections">full loosely connected network</a> by default using a <a href="https://www.erlang.org/doc/apps/kernel/global.html">global process registry</a> if you're managing a small cluster redundant links are fine and welcome, if you can get away with being fully connected -- which isn't possible in a large network. <a href="https://youtu.be/c12cYAUTXXs?t=1745"> Whatsapp had a great talk on opt-ing out of this in 2014! </a>
{{% /callout %}}

2. a tree topology - let's revisit [spanning trees](https://en.wikipedia.org/wiki/Minimum_spanning_tree). We're presented with seemingly contradictory goals - fast low-latency and reliable accurate broadcast, in a 25-node cluster with partitioned networks. What to do?

Let's say each node in a 6 node cluster forms a grid, each possible route from a node to a node:
```
a ++ b ++ c
+    +    +
d ++ e ++ f
```
We can construct a "temporary overlay" over sub portions of this mesh, which is essentially a small tree from the point of view any node say a to its reachable neighbours:
```
    b---/e
   /    \f
a /
  \   /d
   \c
    \
```

This tree is weighted by the cost it takes to reach each neighbour and a _minimum spanning tree_ represents the "cheapest way there", well now that's one way of efficiently routing messages quickly, latency goes down, but... our overall protocol is now more brittle. If an "important" link between small sub-trees is broken the overall protocol is less reliable. Are there hybrid options?

> To keep the number of messages low, while allowing quick recovery in case of a connectivity loss, we can mix both approaches — fixed topologies and tree-based broadcast — when the system is in a stable state, and fall back to gossip for failover and system recovery

I briefly discovered but did not implement other interesting hybrid algorithms/protocols [^5] [^6] [^7] such as PlumTrees(the search term is "epidemic Broadcast Trees"), [SWIM](https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf) used by [Consul's serf](https://www.serf.io/docs/internals/gossip.html), HyParView & HashGraph, and of course [fly.io's corrosion](https://github.com/superfly/corrosion) (built specifically for service discovery) or consul's memberlist[^10] and more!

NB: My [final solution](https://github.com/hailelagi/gossip-glomers/tree/main/maelstrom-broadcast) isn't as efficient as it could be:

It's above the minimum target for "chattiness" ie `30` vs `30.05824` `msgs-per-op` with `--topology tree3` which is `a - [b, c, d]`:
```
 :net {:all {:send-count 55144,
             :recv-count 55144,
             :msg-count 55144,
             :msgs-per-op 32.11648},
       :clients {:send-count 3534, :recv-count 3534, :msg-count 3534},
       :servers {:send-count 51610,
                 :recv-count 51610,
                 :msg-count 51610,
                 :msgs-per-op 30.05824},
       :valid? true},
```

but on target for latency:
```
            :stable-latencies {0 0,
                               0.5 148,
                               0.95 354,
                               0.99 420,
                               1 457},
```

This makes sense, we could shave off even more redundant ack messages by using async `n.Send` which doesn't expect a response/ack, but it makes it more difficult to be able to have timeouts or detect failure reliably a good middle ground is some kind of periodic polling mechanism with a `time.Sleep` empirically eyeballing what might be a good fit or a more sophisticated probabilistic model like [Phi-Accural](https://doc.akka.io/docs/akka/current/typed/failure-detector.html).

I think it's good enough as I've better intuited the trade off here. Maelstrom has a "line", "grid" and several [spanning tree topologies](https://github.com/jepsen-io/maelstrom/blob/main/doc/03-broadcast/02-performance.md#broadcast-latency) by using one kind of network for example across the "line":
```
a ++ b ++ c ++ d ++ e ++ f
```
or "ring" like riak[^5], you loop back around and can pass even fewer messages/duplicates but risk greater latency.


## 4. Grow-Only Counter

Next up is strong eventual consistency with Conflict Free Replicated Data Types! [^15] These allow us to replicate some data say a `count` of an integer `i32` across nodes by being **available and partition tolerant** guaranteeing that at some unknown point in the future, it converges to the same state for every participant, given certain properties are pure, in the functional programming sense ie -- lack side effects like say "addition" of integers and the order in which this operation(s) is carried out doesn't affect the total result, also known as -- commutativity:

```
  +1
(node a)  (node b) (node C)
```

an increment on a is replicated to b and c _eventually_ as:
```
a few moments later...
  +1        +1       +1
(node a)  (node b) (node C)
```

and can as well happen as:

```
  +2                +1
(node a) (node b) (node C)
```

we guarantee somehow, regardless of each addition operation occurs at some time `T_1`, even if another addition occurs concurrently at `T_2`,
because it's _commutative_ , there's no contradiction that affects the final result when the network partition eventually  heals, nor is co-ordination necessary.

```
eventually consistent ヽ(‘ー`)ノ
  +2       +2        +2
(node a) (node b) (node C)
Total count = 6
```

We're given a [sequentially consistent](https://jepsen.io/consistency/models/sequential) key-value store service and can use this to keep track of the current count on each node, each increment is called a `delta`, this **greatly** simplifies the problem:

```go
deadline := time.Now().Add(400*time.Millisecond)
delta := int(body["delta"].(float64))
ctx, cancel := context.WithDeadline(context.Background(), deadline)
defer cancel()

previous, err := s.kv.Read(ctx, fmt.Sprint("counter-", s.node.ID()))

if err != nil {
	result = delta
} else {
	result = previous.(int) + delta
}

err = s.kv.CompareAndSwap(ctx, fmt.Sprint("counter-", s.node.ID()), previous, result, true)
```

and to return the current total count:
```go
  for _, n := range s.node.NodeIDs() {
	  count, _ := s.kv.ReadInt(ctx, fmt.Sprint("counter-", n))

	  result = result + count
}
```

However, say that we don't have a magical `SeqCst` store somewhere to pull out of our pocket for co-ordination of state, there are two approaches in theory:
- operation transform
- state transform

Roughly, sharing only the "delta" or current update ie `add 1` to the current global count is indicative of an **operation-based design** contrasted with sharing the entire the count state a **state-based design**[^8], for an integer this difference might seem trivial but it has deeper implications for more complex data structures, one of the big seeming disadvantages of an operation based representation is it requires **a reliable broadcast** with idempotence/de-duplication, retry ordering and "reasonable" time delivery semantics, which means if you're unlucky... state could diverge permanently, while the state based representation can tolerate partitions slightly more gracefully but requires more data over the wire which **monotonically increases**, which later gets "merged" and makes deletion more complex.

In summary, as long you can guarantee certain properties(associativity, commutativity, idempotence) it's possibly to resolve conflicts between replicas given certain constraints. All we need is an extra "replicate" handler which leverages the previous broadcast from before to [propagate the delta 'operationally'](https://github.com/hailelagi/gossip-glomers/blob/main/maelstrom-g-counter/operation_crdt.go) which often converges correctly but sometimes doesn't? maybe I'm doing it wrong idk.
 
```go
func (s *session) replicateHandler(msg maelstrom.Message) error {
	var body map[string]any
	if err := json.Unmarshal(msg.Body, &body); err != nil {
		return err
	}

	delta := int(body["delta"].(float64))
	localCount += delta

	return s.node.Reply(msg, map[string]any{"type": "replicate_ok"})
}
```


Other varieties exist like `PN Counters` which support subtraction/decrements, the G-Set -- a set and [much richer primitives](https://crdt.tech/papers.html) which includes [tree models that mirror the DOM](https://madebyevan.com/algos/crdt-mutable-tree-hierarchy/) and sharing [JSON!](https://electric-sql.com/blog/2022/05/03/introducing-rich-crdts) but that's enough for now. Libraries that abstract this away and allow you build super cool collaborative multiplayer stuff like google docs and [figma](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/) are: [YJS](https://docs.yjs.dev/yjs-in-the-wild) or [automerge](https://automerge.org/) and elixir/phoenix's very own [Presence](https://hexdocs.pm/phoenix/Phoenix.Presence.html) on the server side which implements the [Phoenix.Tracker](https://hexdocs.pm/phoenix_pubsub/2.1.3/Phoenix.Tracker.html) integrated with websockets and async processes so you can just build stuff, much wow! Ever wondered how discord's "online" feature works? it's CRDTs all the way down, you can [trivially experiment with implementing this in phoenix!](https://hexdocs.pm/phoenix/Phoenix.Presence.html#module-fetching-presence-information)


## 5. Kafka-Style Log
> As Gregor Samsa awoke one morning from uneasy dreams he found himself transformed in his bed into a gigantic insect.

It's a bird, it's a plane... it's tiny kafka! No, not  _[that kafka](https://en.wikipedia.org/wiki/Franz_Kafka)_.
This one's what people use as a message bus, or broker, or messsage queue or event stream, [event sourcing](https://microservices.io/patterns/data/event-sourcing.html) all the words, as it turns out stream processing is a big deal and super important infra[^14]

> Apache Kafka is an open-source distributed event streaming platform used by thousands of companies for high-performance data pipelines, streaming analytics, data integration, and mission-critical applications.

In a nutshell this is a [multi-producer, multi-consumer problem](https://en.wikipedia.org/wiki/Producer%E2%80%93consumer_problem), a [classic computer science/OS concurency problem](https://pages.cs.wisc.edu/~remzi/OSTEP/threads-cv.pdf) aka the "bounded buffer" problem, with _a twist_.

You have 'producer' or writer threads, and 'consumer' threads which process or transform the written data, how to connect the two? -- a shared buffer or 'channel' that both threads can access and synchronize r/w access to.

 go's channel abstraction solves a subset of this generalised problem, yet, here as hinted we have key differences in assumptions:
 
 1. when you read from a channel, this "event" is dequeued or destroyed.
 2. It's **guaranteed** this destructive r/w will happen or it won't, **exactly once**.
 3. There's effectively a **reliable link** between the producing go routine and the consuming go routine, it's just a pointer hop away.
 4. goroutines may panic or fail and be observed to do so immediately, transparently and consistently according to the [runtime memory model](https://go.dev/ref/mem)
 5. Everything happens in main-memory

Each of these assumptions can be sent to `dev/null`:

- the network is unreliable
- failure is everywhere
- latency might as well be failure
- concurrency is weird - duplicates, re-appearing, disappearing.
- time is a lie

Except the first.

In the [classic](https://www.rabbitmq.com/docs/classic-queues) publisher/subscriber model of protocols like [AMQP](https://www.rabbitmq.com/tutorials/amqp-concepts), a publisher "pushes" messages [over the wire](https://www.rabbitmq.com/docs/channels#basics) via a router known as an exchange to the broker which has an [index queue](https://github.com/rabbitmq/rabbitmq-server/blob/main/deps/rabbit/src/rabbit_classic_queue_index_v2.erl) and persistent/on-disk [store queue](https://github.com/rabbitmq/rabbitmq-server/blob/main/deps/rabbit/src/rabbit_classic_queue_store_v2.erl#L10) (durably or transiently) which in turn [actively fowards](https://www.rabbitmq.com/docs/consumers#subscribing) the message to the consumer until it ACKs this message then it is typically destroyed/removed [^9]. 

> The persistent data structure used in messaging systems are often a per-consumer queue with an associated BTree or other general-purpose random access data structures to maintain metadata about messages.
- https://kafka.apache.org/documentation/#design_constanttime

```
Producer                |                |  broker --> |  consumer
Producer -> 'push'      | <- exchange -> |  queue  --> |  consumer
Producer   to exchange  |                |  queue  --> |  consumer
```

However Kafka is a _**log based** message broker_ not a queue.

What's the difference?

This [nice diagram from the docs](https://kafka.apache.org/documentation/) gives an overview at a high level:

![streams and tables](https://kafka.apache.org/images/streams-and-tables-p1_p4.png)

In between producers and consumers is a broker, inside said "broker" server, we have the concept of "topics" basically a set of bounded buffers and partitions in the image: (P1, P2, P3, P4) -- in the spirit of divide and conquer we split up the big problem into little one's, so we can process those individually -- horizontally, in parallel.
 
```
Producer ->            |                           |  <- consumer
Producer -> 'push'     | topics are partitioned    | 'pull' consumer(s)
Producer -> to topic   | over buckets or segments  |  <- consumer
```

However there's a big problem -- this is a distributed system, how do these "bounded buffers" share the same view?

>  we need to ensure that every replica of the log **eventually** contains the
same entries in **the same order** even when some servers **fail** [^16]

We're interested in one neat thing about how it provides a _durable replicated log[^11] [^12] [^13]._ There's a common aphorism in database rhetoric, "the log is the database" - is that true? idk but replicated logs are very useful in distributed systems and databases.[^17]

> Using FIFO-total order broadcast it is easy to build a replicated system: we broadcast every update request to the replicas, which update their state based on each message as it is delivered. This is called state machine replication (SMR)
- https://www.cl.cam.ac.uk/teaching/2122/ConcDisSys/dist-sys-notes.pdf

Can we guarantee a total consistent ordering of the log?

> At its heart a Kafka partition is a replicated log. The replicated log is one of the most basic primitives in distributed data systems, and there are many approaches for implementing one.
- https://kafka.apache.org/documentation/#design_replicatedlog

The log is a totally ordered, immutable grow only sequence of "events" [^18], sound familiar? this suspiciously sounds like a WAL -- and infact it is! Kafka [even has transactions??!](https://www.confluent.io/blog/transactions-apache-kafka/) but more on that later.

> Kafka organizes messages as a partitioned write-ahead commit log
on persistent storage and provides a pull-based messaging
abstraction to allow both real-time subscribers such as online services and offline subscribers such as Hadoop and data
warehouse to read these messages at arbitrary pace. [^16]

Hopefully this explains _why_ a replicated log[^16] [^17], partitions need to have a consistently ordered view, yet how exactly does a log give us these properties? some observations:

1. a position/offset is a "timestamp" independent of a system clock
2. reading state from this position is a **deterministic** process
3. write is simply an atomic `append`, to a cell that is "filled" or "not".
3. an offset is **monotonically increasing** -- fun with binary search!

```
(so many synonmyns!)
entry/tuple/event/message: {key, value, offset}
[{k1, hi, 0}, {k2, hello, 1}, {k2, world, 2}, {k1, foo, 3}, {k3, baz, 4}}]
```

Notice that keys can appear more than once and the latest entry for a key is its "current" value, each offset denotes a version of this event.

To replicate this log, two general approaches are considered [^16] [^20]:
1. primary-backup replication 
2. and quorum-based replication

In a primary-backup setup, we elect and maintain a leader which is responsible for the total order and strong consistency:

> A primary therefore assigns continuous and monotonically increasing serial
numbers to updates and instructs all secondaries to process
requests continuously in this order.

Kafka has historically shippped quorums via a zookeeper/ZAB layer, but has recently provided [raft as an alternative](https://developer.confluent.io/learn/kraft/). Note how the abstractions are layered:

> We rely on the quorum-based Apache Zookeeper service for making
consensus decisions such as leader election and storing critical partition metadata such as replica lists, while using a
primary-backup approach for replicating logs from leader to
followers. The log format is much simpler with such separation since it does not need to maintain any leader election
related information, and the replication factor for the log
is decoupled from the number of parties required for the
quorum to proceed

Which apparently raises interesting questions for operability, durability and delivery semantics folks seem to have strong debates and opinions on. There's a common association between the  WAL and durability, but this is not necessarily true.
In this context, the WAL supports a pattern known as [change data capture](https://en.wikipedia.org/wiki/Change_data_capture).

> All data is immediately written to a persistent log on the filesystem without necessarily flushing to disk. In effect this just means that it is transferred into the kernel's pagecache.
- https://kafka.apache.org/documentation/#design_filesystem

Competitors like redpanda [ship raft](https://docs.redpanda.com/current/get-started/architecture/#raft-consensus-algorithm) while warpstream does interesting things with [distributed mmap](https://www.warpstream.com/blog/minimizing-s3-api-costs-with-distributed-mmap) and stateless agents, a different can of worms.

The challenge is thankfully much simpler -- than having to implement distributed mmap or pulling in something like zookeeper or raft, we have yet again a magical convenient linearizable key value store, damn that's a nice primitive to have lying around. Why?

```go
node := maelstrom.NewNode()
kv := maelstrom.NewLinKV(node)
```

A `lin-kv` is ideally all you need, wheter it's powered by raft or the [sun god Ra](https://en.wikipedia.org/wiki/Ra), we've solved the difficult distributed systems problems of **ordering** and **agreement** across replicas when the leader dies, in the face of network partitions or concurrent servers which accept writes -- one source of truth.

> Kafka dynamically maintains a set of in-sync replicas (ISR) that are caught-up to the leader. Only members of this set are eligible for election as leader. A write to a Kafka partition is not considered committed until all in-sync replicas have received the write

In this much more simplistic model, a commit can simply block until it reaches the `lin-kv` source of truth.

Abstracting away the messaging boilerplate the data structure is:

```go
type replicatedLog struct {
	committed map[string]float64
	version   map[string][]int
	log       []entry
	pLocks    []*sync.RWMutex
	global    sync.RWMutex
}

type entry struct {
	key    string
	value  float64
	offset float64
}
```

- a producer can send an "event" or message to be appended:
```go
// This is inefficient. In a real implementation
// this would be a CAS against an atomic pointer or 
// an atomic CoW memswap // for simplicity and sanity, 
// a simple mutual exclusion lock is used
// obviously this contends the local lock on this service.
func (l *replicatedLog) Append(kv *maelstrom.KV, key, value any) int {
	l.global.Lock()
	defer l.global.Unlock()

        // acquire a monotonic counter from the `lin-kv`
	offset := l.acquireLease(kv)
	k, v := key.(string), value.(float64)
	event := entry{key: k, value: v, offset: float64(offset)}

	l.log[offset] = event
	l.version[key.(string)] = append(l.version[key.(string)], offset)

	return offset
}
```

-  a consumer can ask or poll for new events:
```go
// Read messages from a set of logs starting from the given offset in each log
func (l *replicatedLog) Read(offsets map[string]any) map[string][][]float64 {
	l.global.RLock()
	defer l.global.RUnlock()

	var result = make(map[string][][]float64)

	for key, offset := range offsets {
		// resolve the replica's committed history
		result[key] = l.seek(key, int(offset.(float64)))
	}

	return result
}
```

- a client can synchronise processed offsets with the server(s):
```go
// Commit ack the last offset a client should read from by the server
func (l *replicatedLog) Commit(kv *maelstrom.KV, offsets map[string]any) {
	ctx, cancel := context.WithDeadline(context.Background(), time.Now().Add(400*time.Millisecond))
	l.global.Lock()
	defer l.global.Unlock()
	defer cancel()

	for key, offset := range offsets {
		l.committed[key] = offset.(float64)
		kv.Write(ctx, key, offset)
	}
}
```

- a client can read from the latest committed offset:
```go
// ListCommited view the current committed offsets ack'd by the server
func (l *replicatedLog) ListCommitted(kv *maelstrom.KV, keys []any) map[string]any {
	ctx, cancel := context.WithDeadline(context.Background(), time.Now().Add(400*time.Millisecond))
	l.global.Lock()
	defer l.global.Unlock()
	defer cancel()

	var offsets = make(map[string]any)

	for _, key := range keys {
		key := key.(string)
		lastCommitted, _ := kv.Read(ctx, key)

		if lastCommitted == nil {
			continue
		} else {
			l.committed[key] = float64(lastCommitted.(int))
			offsets[key] = float64(lastCommitted.(int))
		}
	}

	return offsets
}
```
Because this is a toy, the log grows forever, that's not okay  -- compaction is [it's own can of worms](https://kafka.apache.org/documentation/#design_compactionbasics). The log is also not persisted, which it would have to be in a real implementation as these datasets are typically large record batches, it's also inefficient.

All anyone has to do to build on this knowledge and make actual real life kafka is [build literally everything else for the rest of your life](https://kafka.apache.org/documentation/#implementation).

![unfinished horse](/unfinished_horse.png)


## 6. Totally-Available Transactions

Finally, a distributed key-value store with transactions, or rather something simpler resembling the real thing.
I promised we would revist transactions, why and how kafka offers these semantics and demystifying transactions in general, here we are!

Transactions are a deep topic but first ACID, we're interested in specifically the 'C' in there first - consistency. Before a bunch of theory what's our goal here?

- weak consistency (here be dragons!)
- total availability (in CAP terms - AP)

We'll revisit why these semantics matter. Let's focus on understanding the **requirements** as we go,
we need to define a handler that takes a single message/data structure with list of `operations` that look like:

 `[["r", 1, null], ["w", 1, 6], ["w", 2, 9]]`.

which means our handler needs to:
- read from kv[1]
- write to kv[1]=6
- write to kv[2]=9

we can re-use the `store` from earlier as a key-value store:
```
type store struct {
	index map[int]int
	log   []float64
}
```

all there is to figure out is the parsing for the above semantics:

```go
	kv := s.kv

	txn := body["txn"].([]any)
	var result = make([][]any, 0)

	for _, op := range txn {
		op := op.([]any)

		if op[0] == "r" {
			index := op[1].(float64)

			result = append(result, []any{"r", index, kv.log[int(index)]})
		} else if op[0] == "w" {
			index := op[1].(float64)
			value := op[2].(float64)
			kv.log[int(index)] = value

			result = append(result, []any{"w", index, kv.log[int(index)]})
		}
	}
```

we try out empirically our first consistency model `read uncommitted`:

```
Everything looks good! ヽ(‘ー`)ノ
```

huh -- that was easy? what's all the fuss about these SQL anomalies and stuff? dirty writes? phantom skews? [^19]

> Read uncommitted is a consistency model which prohibits dirty writes, where two transactions modify the same object concurrently before committing. In the ANSI SQL specification, read uncommitted is presumed to be the default

but of course there's no free lunch, not really.

> The ANSI SQL 1999 spec places essentially no constraints on the behavior of read uncommitted. Any and all weird behavior is fair game.
- https://jepsen.io/consistency/models/read-uncommitted

There are "bugs" here, just depends on what the agreed upon definition is [^21] -- in a sense, is what isolation and consistency models are really about. What are the semantics and rules can we agree on what is desired behaviour? is it fast?

## 7. Testing, Model Checkers and Simulators
If you've been wondering, since these are just toy models, what's the delta between these simplified ideas and the real world?

Where are the "unit tests"? If maelstrom/jepsen says so, does it make these implementations correct? maybe.

Intuitively, if you've gotten this far, you should feel in your bones, distributed systems are different from single node ones.
The way we test them must change, because they require a fundamental shift in thinking to reason about and therefore verifying correctness of primitives. This is a hard problem with no easy answers. An overview of interesting things to explore in the space:

- [TLA+](https://lamport.azurewebsites.net/tla/tla.html)
- [Hermitage](https://martin.kleppmann.com/2014/11/25/hermitage-testing-the-i-in-acid.html)
- Deterministic simulation testing: ala [foundationdb](https://apple.github.io/foundationdb/testing.html), [tigerbeetle's vopr](https://github.com/tigerbeetle/tigerbeetle/blob/main/src/vopr.zig), [antithesis](https://antithesis.com/docs/introduction/how_antithesis_works.html) and much more I probably haven't discovered.


If that sounds like a pretty high bar for correctness **it's because it is**. Verifying the correctness of distributed systems is a non-trivial problem, when building applications implictly there's trust that the claimed semantics are true, composing them properly is a different matter entirely. This will be cursory high level overview of elle [^22] the model checker which powers a fair bit of some the invariant checks here.

![Gyomei Himejima - Good for you for seeing it through](/good.png)

and that's it! fun with distributed systems, scalability but [at what COST?](https://www.usenix.org/system/files/conference/hotos15/hotos15-paper-mcsherry.pdf), here's LMAX doing [100k TPS in < 1ms](https://www.infoq.com/presentations/LMAX/) in 2010 on a single thread of "commodity hardware", [distributed systems are a necessary evil requiring a different lens](https://www.somethingsimilar.com/2013/01/14/notes-on-distributed-systems-for-young-bloods/).

{{% callout color="#ffd700" %}}
If you enjoyed reading this please consider thoughtfully sharing it with someone who might find it interesting!
{{% /callout %}}

### References

[^1]: https://datatracker.ietf.org/doc/html/rfc4122#section-4.2.1
[^2]: https://en.wikipedia.org/wiki/Snowflake_ID
[^3]: http://yellerapp.com/posts/2015-02-09-flake-ids.html
[^4]: https://www.cockroachlabs.com/blog/living-without-atomic-clocks/
[^5]: https://docs.riak.com/riak/kv/2.2.3/learn/concepts/clusters.1.html
[^6]: https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf
[^7]: https://highscalability.com/gossip-protocol-explained/
[^8]: https://www.cs.utexas.edu/~rossbach/cs380p/papers/Counters.html
[^9]: https://www.rabbitmq.com/docs/confirms#acknowledgement-modes
[^10]: https://github.com/hashicorp/memberlist
[^11]: https://mesos.apache.org/documentation/latest/replicated-log-internals/
[^12]: https://en.wikipedia.org/wiki/State_machine_replication
[^13]: https://blog.x.com/engineering/en_us/topics/infrastructure/2015/building-distributedlog-twitter-s-high-performance-replicated-log-servic
[^14]: http://dist-prog-book.com/chapter/9/streaming.html
[^15]: https://inria.hal.science/inria-00555588/document
[^16]: https://www.vldb.org/pvldb/vol8/p1654-wang.pdf
[^17]: https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying
[^18]: https://www.cs.cornell.edu/fbs/publications/ibmFault.sm.pdf
[^19]: https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tr-95-51.pdf
[^20]: https://www.microsoft.com/en-us/research/wp-content/uploads/2008/02/tr-2008-25.pdf
[^21]: https://pmg.csail.mit.edu/papers/icde00.pdf
[^22]: https://www.vldb.org/pvldb/vol14/p268-alvaro.pdf
