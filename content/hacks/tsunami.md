---
title: "Making a Tsunami"
date: 2023-12-23T00:19:58+01:00
draft: false
tags: rust, erts, wasm, k-v store
recommend: false
---

WIP public draft, come back later. <https://github.com/hailelagi/wavl-ets>

Last updated: 12th Jan 2023.

# Outline

This was one of the first really hard ambitious things I tried to build, but sadly because of
either a lack time, grit or knowledge/skill I just couldn't make meaningful progress.

To be fair - at first it _seemed_ like a simple "good first issue" kind of thing I had no idea what I was opting into, so here's a disclaimer!
We're going to build a type of database! No It's not enough machinery akin to say postgres but there's a fair bit of stuff going on!

Give or take some pre-requisites:

- some knowledge of programming - you've built/know what a crud app is
- an idea of rust's ownership system or exposure to some memory management ala C, C++ or Zig
- a rough sense of lexical parsing
- some idea about trees and or graph traversal in general
- some concurrency (shared state or message passing)
- Some knowledge of go's syntax/semantics or a similar C syntax based language like javascript

This covers some wide ranging and complex important topics, it's impossible to explain everything indepth clearly nor do I have the expertise/knowledge to do so, there are likely gaps or subtle errors -- but I'll try. Bonus helpful concepts for a google search/chatGPT (but not critical):

- What is the BEAM? What is the erlang runtime system?
- What is garbage collection?
- Scheduling - how does a runtime handle IO? what's a syscall?
- Atomics/Compare & Swap/Test & Set, what is a critical section?
- What is a CPU Register/cache line movement?
- uniprocessors vs multiprocessors(SMP/MIMD)?

You've been warned! Grab a coffee or tea and let's scope it out! I'll be using a mixture of go/rust for the examples.

## Shaping performance constraints

Before we get into the bells and whistles of it all, what are we _really_ trying to achieve? Conceputally a key-value store is simple.
What you want is an abstract interface that can store data and retrieve it fast, essentially a map/dictionary/associative array abstract data type:

```go
type Table[Key comparable, Value any] interface {
  Read(Key) (Value, error)
  Write(Key, Value)
  Delete(Key)
  In(Key) bool
}
```

and you might be thinking why not just throw a hashmap underneath and that works! Infact hashmaps are ubiquitious and contain excellent
properties, however most implementations in standard libraries are not thread safe. CPU cores need to synchronize data access to avoid corrupting data or reading inconsistent or stale data.

In rust - sharing an `std::collections::hash_map::HashMap` requires wrapping it in two things:

1. an atomic reference count `Arc<T>`
2. a mutex or some other sync mechanism because the type does not impl `Send` & `Sync`

If your data only has to exist within a single thread that's great, but applications tend to need to handle _concurrent_ data access.
Practical examples of this are caches, rate limiting middleware, session storage, distributed config, simple message queues etc

Let's wrap it in a mutex from std lib's `sync` package:

```go
type Map[K string, V any] struct {
 sync.Mutex
 Data map[K]V
}
```

To `Read` and `Write` we must acquire `*Map.Lock()` and release `*Map.Unlock()`. This works, up to a point --
but we can do better! We're trying to build a _general purpose_ data store for
key-value data. Global Mutexes are a good solution but you tend to deal with _lock contention_ on higher values of R/W data access,
especially where your hardware allows parallel access when the underlying memory region's slots are partioned due to hashing across independent regions.

A clever way of getting around this is by using an advanced concurrency technique called fine-grained locking, the general idea is instead of a global mutex we serialise access to specific partitions[1]:

```go
type Map [K string, V any] struct {
 Data  map[K]V
 locks []*sync.Mutex
 global sync.Mutex
}
```

This is much more complex but can be more write performant but suffer slighly slower reads. The bottleneck of mutexes and serialisation is the reason databases like postgres and mysql have Multi Version Concurrency Control(MVCC) semantics for pushing reads and writes further using transactions. We'll come back to exploring this concept and its tradeoffs.

Next, we'd like to be able to store both ordered and unordered key value data, hash maps store unordered data so this calls for some sort of additional data structure with fast ordered abstract Map operations. We must redefine our interface, depending on our needs, we'll want different abstract properties:

```go
type OrderTable[Key cmp.Ordered, Value any] interface {
 Get(Key) (Value, error)
 Put(Key, Value)
 Del(Key)
 In(Key) bool
}
```

For a concrete implementation, let's start with the conceptually simplest/fastest* the Binary Search Tree and a global RWMutex:

```go
type BST[Key cmp.Ordered, Value any] struct {
 key   Key
 value any

 parent *BST[Key, Value]
 left   *BST[Key, Value]
 right  *BST[Key, Value]

 global sync.RWMutex
}
```

Search trees are the "go to" structure for keeping performant ordered data with balanced read/write performance, by ensuring we keep the "search property" we can perform on average operations in O(logN) -- if the tree is balanced. Sadly they're bounded by the worst time-complexity of O(h) where h is the height of the tree. What that means is if we get unlucky
with the data - searches can devolve into searching a linked-list. That wouldn't do. Here there are many flavors thankfully.

Fan favorites include the classics; an AVL Tree, B-Tree or perhaps an LSM Tree, which all come with spices and even more variety.

In practice we are concerned about much more than order of magnitude choices, we are also interested in how these structures
layout in memory, are the leaves holding a page cache? - there's a fundamental difference between sorting data that can fit in main memory (internal) and
sorting data that exists on disk(external), what kind of concurrent access patterns are enabled? how do they map to our eventual high level API?

This is where conceptually we take a different road from what exists in the current erlang runtime system. The data structure chosen previously of which we'll be benchmarking against is something called a Contention Adapting Tree [2]. Briefly a CA Tree, dynamically at runtime changes the behaviour and number of locks it holds across the tables it protects depending on nature of contention.

What are we finally choosing to implement, why?

## The dumpster fire that is garbage collection

So far we haven't really had to worry about garbage collection. A brief mention of rust mentioned using atomic reference counts, and in go where this operation
is automatic and opaque to the user we didn't have to worry about it. The resource allocation strategy is tightly coupled to the programming language and environment
we intend our concrete key value implementation to eventually live, so at this point we bid farewall to go and carry on with the intricacies of
low-level memory management.

## A detour for just enough web assembly

tdlr; crash course in just enough webassembly

## Concurrency, Correctness & Going web scale - are you ACID compliant? 👮

These days are you a serious software craftsman [if you're not at web scale?](https://www.youtube.com/watch?v=b2F-DItXtZs).

In our undying, unending pursuit to scale systems further and further we spin webs of complexity. [Why? who knows, it's provocative.](https://www.youtube.com/watch?v=RlwlV4hcBac)

Let's scale! Previously we mentioned fine-grained locking as a technique that could lead to better write performance but at the cost of complexity and read performance -- a related application of this technique is called "sharding". Most databases need to ensure certain guarantees with respect to performance, concurrency and correctness. This is commonly encapsulated with ACID - Atomicity, Consistency, Isolation and Durability. Lucky for us, we can cast away the durability requirement as our data set must fit in working memory.

That leaves us with:

- Atomicity
- Consistency
- Isolation

what to be done etc

# Gotta Go Fast

at what cost?

- use of lock free data structures/behaviour across reads - concurrent skip list crash course, why?

intro to lock free techniques[3]

## More complex Types

- conformance and integration with/into the firefly runtime

So far these examples have been somewhat generic but the underlying implementation only allowed simple types a key of type `string` and a value of `int`.
This is intentionally done in order not to distract from other concepts, but if we really want a general key value store we need to allow many types.
In this case we want to allow every type supported by the erlang runtime systems.

## The query parser

Every good database needs ergonimics features fo good querying! SQL is amazing but is insanely complex to implement and tightly coupled to transaction semantics,
however we don't want to feel left out, let's build a tiny(compared to sql) query syntax and engine.

## Testing & Benchmarks

- unit testing challenges, tight coupling etc
- conformance with the upstream erts(erlang runtime system) ETS public api and behaviour
- 100% erts TEST SUITE coverage

methodology, coverage, tools, loom, address sanitizer etc insert graphs of benchmark results

## References

- [1] [On the scalability of the Erlang term storage](http://doi.acm.org/10.1145/2505305.2505308)
- [2] [More Scalable Ordered Set for ETS Using Adaptation](https://doi.org/10.1145/2633448.2633455)
- [3] [Lockless Programming Considerations for Xbox 360 and Windows](https://learn.microsoft.com/en-gb/windows/win32/dxtecharts/lockless-programming?redirectedfrom=MSDN)

## What's a Mutex really it's just a sephamore

In a reader-writer lock, a read acquisition has to be visible to
writers, so they can wait for the reads to finish before succeeding to take a write lock. One way to implement this is to have
a shared counter that is incremented and decremented atomically
when reading threads are entering and exiting their critical section.
