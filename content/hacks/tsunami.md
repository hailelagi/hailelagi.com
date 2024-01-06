---
title: "Making a Tsunami"
date: 2023-12-23T00:19:58+01:00
draft: false
tags: rust, erts, wasm, k-v store
recommend: false
---

WIP public draft, come back later. <https://github.com/hailelagi/wavl-ets>

Last updated: 6th Jan 2023.

# Outline

This was one of the first really hard ambitious things I tried to build, but sadly because of
either a lack time, grit or knowledge/skill I just couldn't make meaningful progress.

To be fair - at first it _seemed_ like a simple "good first issue" kind of thing I had no idea what I was opting into, so here's a disclaimer!
We're going to build a type of database! No It's not enough machinery akin to say postgres but there's a fair bit of stuff going on!

Give or take some of the outline:

- some knowledge of programming - you've built a crud app
- an idea of rust's ownership system or exposure to some memory management ala C, C++ or Zig.
- a rough sense of lexical parsing
- some idea about trees and or graph traversal in general
- some concurrency (shared state or message passing)
- Garbage collection in a managed runtime
- Scheduling - how does a runtime handle busy CPU/IO?

Bonus(but not important):

- Atomics/Compare & Swap
- Some exposure to the CPU Cache/cache line movement
- Some knowledge of the BEAM - elixir or erlang (especially :ets)
- Some knowledge of go's syntax/semantics

You've been warned! Grab a coffee or tea and let's scope it out! I'll be using a mixture of go/rust for the examples.

## Shaping performance constraints

Before we get into the bells and whistles of it all, what are we _really_ trying to achieve? Conceputally a key-value store is simple.
What you want is an abstract interface that can store data and retrieve it fast, essentially a map/dictionary/associative array abstract data type:

```go
type Store[Key comparable, Value any] interface {
  Read(Key) (Value, error)
  Write(Key, Value)
  Delete(Key)
  In(Key) bool
}
```

and you might be thinking why not just throw a hashmap underneath and that works! Infact hashmaps are ubiquitious and contain excellent
properties, however most implementations in standard libraries are not thread safe.

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

A clever way of getting around this is by using an advanced concurrency technique called fine-grained locking, the general idea is instead of a global mutex
we serialise access to specific partitions[1]:

```go
type Map [K string, V any] struct {
 Data  map[K]V
 locks   map[K]*sync.Mutex
 global sync.Mutex
}
```

This is much more complex but can be more performant. This bottleneck is the reason databases like postgres and mysql have Multi Version Concurrency Control(MVCC)
semantics for reading and writing using transactions. We'll come back to exploring this concept. Next, we'd like to be able to store both ordered and unordered key
value data, hash maps store unordered data so this calls for some sort of additional self balancing tree data structure.

Let's go with the conceptually simplest the Binary Search Tree:

```go
type BST[K comparable, V any] struct {
  // todo
}
```

## The dumpster fire that is garbage collection

So far we haven't really had to worry about garbage collection. A brief mention of rust mentioned using atomic reference counts, and in go where this operation
is automatic and opaque to the user we didn't have to worry about it. The resource allocation strategy is tightly coupled to the programming language and environment
we intend our concrete key value implementation to eventually live, so at this point we bid farewall to go and carry on with the intricacies of
low-level memory management.

## More complex Types

So far these examples have been somewhat generic but the underlying implementation only allowed simple types a key of type `string` and a value of `int`.
This is intentionally done in order not to distract from other concepts, but if we really want a general key value store we need to allow many types.
In this case we want to allow every type supported by the erlang runtime systems.

## The query parser

Every good database needs ergonimics features fo good querying! SQL is amazing but is insanely complex to implement and tightly coupled to transaction semantics,
however we don't want to feel left out, let's build a tiny(compared to sql) query syntax and engine.

## Scope/Goals

- conformance with the upstream erts(erlang runtime system) ETS public api and behaviour
- 100% erts TEST SUITE coverage
- use of lock free data structures/behaviour across reads
- conformance and integration with/into the firefly runtime

## References

- [1] [On the scalability of the Erlang term storage](http://doi.acm.org/10.1145/2505305.2505308)
- [2] [More Scalable Ordered Set for ETS Using Adaptation](https://doi.org/10.1145/2633448.2633455)
