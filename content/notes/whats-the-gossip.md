---
title: "Gossip Girl"
date: 2024-04-20T09:38:39+01:00
draft: true
---

Documenting solving the fly.io distributed systems challenges.

## 1. echo
saying hello world! but distributed systems style, it's mostly boilerplate setup, 
reading the maelstrom docs and the go client docs or building one in rust to instantiate a maelstrom Node, define an RPC style handler and returning messages:

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

In a single node system generation of unique ids is typically achieved using either a growing seq int, perhaps an int64 or a one way hashing function(databases automagically do this), it is often not necessary that this hashing function is cryptographically secure(see [1]) only that given an input(such as a monotonic number(system clock), sequential growing counter(for loop) or a pseudo-random bit/string) it produces a unique hash uniformly distributed over the key space 2**(whatever bit) - 1 and the probability of a collision is extremely rare.

In the runtime of a distributed system where each node has its own view of the world there needs to be someway of guaranteeing that input/seed of the hash function as the system clock is unreliable

Alternatives:

Use a really large key space (2**128 - 1) - a uuid.
Generate a snowflake which combines various properties for e.g a timestamp + a logical_id (where it came from) + a sequence_id, Luckily there are no requirements on space or ordering or searching or storage of the ids.
Use a central server to generate ids.
Relation to time and ordering
One of the seeds of a unique id generator are timestamps and hence the concept of time in a distributed system seems relevant but these are distinct concepts. The use of a central authority such as an atomic clock or a "time server" or a lamport/logical clock is about ordering of events and precision while uuids mostly care about uniqueness where time is a seed not necessarily monotonicity.

```go
func genNaiveUUID(nodeID string) int64 {
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

## 3. Broadcast

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

[^1] https://datatracker.ietf.org/doc/html/rfc4122#section-4.2.1