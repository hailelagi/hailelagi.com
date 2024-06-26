---
title: "Call Me Maybe?"
date: 2024-06-23T23:16:51+01:00
draft: false
tags: go, distributed-systems
---
⚠️⚠️⚠️⚠️
This a WIP draft
⚠️⚠️⚠️⚠️

I ~~am solving~~ solved the fly.io distributed systems challenges for practice ~~while reading~~ during and after reading, re-reading & re-reading! part II of database internals with the [sysdsgn bookclub](https://x.com/sysdsgn). The last chapter review was great! With these practice challenges I'll be putting the book away.

The title of this post is inspired by [kyle kingsbury' series of articles like this one](https://aphyr.com/posts/316-call-me-maybe-etcd-and-consul) and [this one](https://aphyr.com/posts/315-call-me-maybe-rabbitmq) and of course:

{{< spotify type="track" id="20I6sIOMTCkB6w7ryavxtO" >}}

## 1. echo
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


## 2. Unique ID Generation (What time is it?)

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


and finally we optimise! we're sending far too many messages and flooding the entire network! even if it's impossible to be both accurate and fast, 
we try anyway -- gotta get those p99s up, so far these are rookie numbers! there's a hint about network topology so let's re-examine that:
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
```diff
-- // spam everyone in this network we know of, and so on...
-- for _, dest := range n.NodeIDs()
++ // send to our "overlay" neighbors only
++ for _, dest := range neighbors
```


[Database Internals chapter 12](https://learning.oreilly.com/library/view/database-internals/9781492040330/ch12.html) and the [maelstrom docs](https://github.com/jepsen-io/maelstrom/blob/main/doc/03-broadcast/02-performance.md) were also super helpful on where to go about exploring options, network topologies for broadcast are a deep topic, so we'll only review a very tiny subset we're interested in:
1. a fully connected grid mesh (what we had before) [to quote wikipedia](https://en.wikipedia.org/wiki/Network_topology):
>  Networks designed with this topology are usually very expensive to set up, but provide a high degree of reliability due to the multiple paths for data that are provided by the large number of redundant links between nodes

(side note: I've worked on a system which delivered rpc messages as a [full loosely connected network](https://www.erlang.org/doc/system/distributed.html#node-connections) using a [global process registry](https://www.erlang.org/doc/apps/kernel/global.html) this heavily depends on cluster size and messaging patterns, if you can get away with being fully connected - you probably should.)

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

I briefly discovered but did not implement other interesting hybrid algorithms/protocols [^5] [^6] [^7] such as PlumTrees(the search term is "epidemic Broadcast Trees"), [SWIM](https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf) used by [Consul's serf](https://www.serf.io/docs/internals/gossip.html), HyParView & HashGraph, and of course [fly.io's corrosion](https://github.com/superfly/corrosion) (built specifically for service discovery) and more!

NB: My [final solution](https://github.com/hailelagi/gossip-glomers/tree/main/maelstrom-broadcast) isn't as efficient as it could be:

It's above the minimum target for "chattiness" ie `30` `msgs-per-op` with `--topology tree4`:
```
 :net {:all {:send-count 67072,
             :recv-count 67072,
             :msg-count 67072,
             :msgs-per-op 38.680508},
       :clients {:send-count 3568, :recv-count 3568, :msg-count 3568},
       :servers {:send-count 63504,
                 :recv-count 63504,
                 :msg-count 63504,
                 :msgs-per-op 36.622837},
 }
```

but on target for latency:
```
:stable-latencies {0 0, 0.5 87, 0.95 259, 0.99 322, 1 373},
```

but I think it's good enough as I've intuited the trade off here. Maelstrom has a "line", "grid" and several [spanning tree topologies](https://github.com/jepsen-io/maelstrom/blob/main/doc/03-broadcast/02-performance.md#broadcast-latency) by using one kind of network for example:
```
a ++ b ++ c ++ d ++ e ++ f
```
across the "line" or "ring", if you loop back around, you can pass fewer messages/duplicates but risk greater latency.

## 4. Grow-Only Counter/G-Counter

Next up is strong eventual consistency with Conflict Free Replicated Data Types! (mouthful!) Specifically lets try an operation-based Commutative Replicated Data Types (CmRDTs)[^8] to implement one. If those sound like fancy words another way to put it is you can replicate some data say a `count` across nodes by being **available and partition tolerant** guaranteeing that eventually it converges to a stable state given that the "operations" are pure -- lack side effects like say "addition" and the order in which this operation is carried out doesn't affect the result -- commutative:

```
  +1
(node a)  (node b) (node C)
```

an increment on a is replicated to b and c _eventually_ as:
```
  +1        +1       +1
(node a)  (node b) (node C)
```

and can as well happen as:

```
  +2                +1
(node a) (node b) (node C)
```

we guarantee somehow, regardless of each addition operation occurs at some time `T_1`, even if another addition occurs concurrently at `T_2`,
because it's _commutative_ , there's no contradiction that affects the final result when the network partition eventually  heals.

```
  +2       +2        +2
(node a) (node b) (node C)
```

We're given a sequentially consistent key-value store service and use this to keep track of the current count, each increment is called a `delta`:

```go
// addOperation
delta := int(body["delta"].(float64))
previous, _ := s.kv.Read(ctx, "counter")
s.kv.CompareAndSwap(ctx, "counter", previous, result, true)

// readOperation
count, _ := s.kv.ReadInt(ctx, "counter")
```

OR to share the counter state and implement a **state-based design CvRDT**[^8] I did not go down this rabbit hole, but it might be interesting, one of the big seeming disadvantages of an operation based representation is it requires **a reliable broadcast** while the state based representation can tolerate partitions much more gracefully in the event of a network partition as long you can guarantee certain properties(associativity, commutativity, idempotence) and merge to resolve conflicts between replicas.

Other varieties exist like `PN Counters` which support subtraction/decrements, the G-Set -- a set and [much richer primitives](https://crdt.tech/papers.html) but that's enough for now. Libraries that abstract this away and allow you build super cool collaborative multiplayer stuff like google docs on the client! see [YJS](https://docs.yjs.dev/yjs-in-the-wild) or [automerge](https://automerge.org/) and elixir/phoenix's very own [Presence](https://hexdocs.pm/phoenix/Phoenix.Presence.html) on the server side which implements the [Phoenix.Tracker](https://hexdocs.pm/phoenix_pubsub/2.1.3/Phoenix.Tracker.html) integrated with websockets and async processes so you can just build stuff, much wow!

## 5. Kafka-Style Log
It's a bird, it's a plane... it's tiny kafka! No, not  _[that kafka](https://en.wikipedia.org/wiki/Franz_Kafka)_.
This one's what people use as a message bus, or broker, or messsage queue or event stream, [event sourcing](https://microservices.io/patterns/data/event-sourcing.html) etc take your pick - if you're familiar with RabbitMQ or Redpanda you get the basic gist.

> Apache Kafka is an open-source distributed event streaming platform used by thousands of companies for high-performance data pipelines, streaming analytics, data integration, and mission-critical applications.

This [nice diagram from the docs](https://kafka.apache.org/documentation/) gives an overview of kafka's high level operations:

![streams and tables](https://kafka.apache.org/images/streams-and-tables-p1_p4.png)

We're interested in one neat thing about how it provides a _durable replicated log._ There's a common aphorism in database rhetoric, "the log is the database" - is that true? idk but replicated logs are very useful in distributed systems and databases.

> At its heart a Kafka partition is a replicated log. The replicated log is one of the most basic primitives in distributed data systems, and there are many approaches for implementing one.
- https://kafka.apache.org/documentation/#design_replicatedlog

```go
```

## 6. Totally-Available Transactions

```go
```

![Gyomei Himejima - Good for you for seeing it through](/good.png)

and that's it! Distributed systems are hard! These concepts are supposed to be _basics_ from which we compose and build higher level abstractions like libraries, tools and applications. Scalability but [at what COST?](https://www.usenix.org/system/files/conference/hotos15/hotos15-paper-mcsherry.pdf), here's LMAX doing [100k TPS in < 1ms](https://www.infoq.com/presentations/LMAX/) in 2010 on a single thread of "commodity hardware", [distributed systems are a necessary evil requiring a different lens](https://www.somethingsimilar.com/2013/01/14/notes-on-distributed-systems-for-young-bloods/), do not self inflict unecessarily.
 
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

