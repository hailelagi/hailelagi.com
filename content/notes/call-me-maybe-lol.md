---
title: "Oops - Call Me Maybe?"
date: 2024-04-20T09:38:39+01:00
draft: true
---

I'm solving the fly.io distributed systems challenges for practice while reading part II of database internals. The title of this post is inspired by [kyle kingsbury' series of articles like this one](https://aphyr.com/posts/316-call-me-maybe-etcd-and-consul) and [this one](https://aphyr.com/posts/315-call-me-maybe-rabbitmq). I thought it'd also be funny to play it on repeat while solving/writing some of this :)

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

In the view of a distributed system where each node could increment this counter simultaneously and the [the system clock is unreliable](https://tigerbeetle.com/blog/three-clocks-are-better-than-one) there needs to be some way of solving this [global clock synchronisation problem](https://www.youtube.com/watch?v=mAyW-4LeXZo) of not only skewing different "times" but logical ordering of events. What to do?

1. A pseudo logical event clock where we can represent casual dependencies as combinations of properties of our system for e.g the system clock + orignating node id + a random request id(tie breaker). Luckily for this challenge there aren't requirements for **space** or **ordering** or **causality**, only **global uniqueness**, which is naive but isn't too far off more sophisticated schemes [^1] [^2]

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

3. The use of a central authority such as an atomic clock or a "time server".

## 3. Broadcast

Our first "official" distributed algorithm! a way to gossip information to nodes. Incrementally we scaffold basic messaging,
sending data efficiently, simulating network partitions, variable latencies and interesting node topologies!

We keep all data we've seen in-memory in a simple "store":
```go
type Store struct {
	index map[float64]bool
	log   []float64
	sync.RWMutex
}

// a session is an instance of a node
// that can read/write from a single-store
// and `handle` messages
type Session struct {
	node  *maelstrom.Node
	store *Store
}
```

reading, we simply take a `read` lock, respond with what's in our `log` so far.

If we get a `broadcast` message we concurrently attempt to send it to all our neighbours,  excluding ourself, store it in `log` and `index` so we can test if we've seen this message before and handle duplicate broadcasts:
```go
for _, dest := range n.NodeIDs() {
	wg.Add(1)

	deadline := time.Now().Add(400*time.Millisecond)
	bgd := context.Background()
	ctx, cancel := context.WithDeadline(bgd, deadline)
	defer cancel()

	go func(dest string) {
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

Our failure detection algorithm is a FIFO queue using go's channels, so we can handle network partitions and variable latency! 
We send messages into a buffered channel, in our else bloc and read it (if/when) we have to retry in a seperate goroutine:
```
s.retries <- Retry{body: body, dest: dest, attempt: 20, err: err}
```

What suprised me is the configuration of this queue. Too small and messages will build up and the `failureDetector`
will eventually never catch up as its starved, too big and the  -- I take solace in the fact:

> A perfect timeout-based failure detector exists only in a synchronous crash-stop system with reliable
links; in a partially synchronous system, a perfect failure detector does not exist

The spurious errors and on/off successes and failures making this were... interesting to debug!

```go
// a naive eventually perfect failure detector :)
func failureDetector(n *maelstrom.Node, retries chan Retry) {
  for retry := range retries {
	  go func(retry Retry) {
		  ctx, cancel := context.WithDeadline(context.Background(), time.Now().Add(400*time.Millisecond))
		  defer cancel()

		  retry.attempt--

		  if retry.attempt >= 0 {
			  _, err := n.SyncRPC(ctx, retry.dest, retry.body)

			  if err != nil {
				  jitter := time.Duration(rand.Intn(100) + 100)
				  time.Sleep(jitter * time.Millisecond)
				  retries <- retry
			  }
		  } else {
			  log.SetOutput(os.Stderr)
			  log.Printf("message slip loss beyond tolerance from queue %v", retry)
		  }
	  }(retry)
  }
}
```

and finally we optimise! we're sending far too many messages!, even if it's impossible to be both accurate and fast, 
we try anyway -- gotta get those p99s up, so far these are rookie numbers!

```go
```


## 4. Grow-Only Counter

```go
```

## 5. Kafka-Style Log

```go
```

## 6. Totally-Available Transactions

```go
```

### References

[^1]: https://datatracker.ietf.org/doc/html/rfc4122#section-4.2.1
[^2]: https://en.wikipedia.org/wiki/Snowflake_ID
