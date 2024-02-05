---
title: "Making a Tsunami"
date: 2023-12-23T00:19:58+01:00
draft: false
tags: rust, k-v store
publicDraft: true
recommend: true
---

# Introduction

This was one of the first really hard ambitious things I tried to build, but sadly because of
either a lack time, grit or knowledge/skill I just couldn't make meaningful progress.

To be fair - at first it _seemed_ like a simple "good first issue" kind of thing I had no idea what I was opting into, so here's a disclaimer!
We're going to build a type of database! Specifically an in-memory key-value data store -- like Redis! kinda... sorta.

But before that context, here's Joe Armstrong explaining why writing correct, fast, well-tested, concurrent & parallel(distributed) programs on modern CPUs is complex and difficult and why erlang/elixir is appealing, it comes with a concurrent/parallel garbage collector (no global GC pauses, **low-latency by default**), a **shared nothing architecture** that's **multi-core by default** and scales IO bound soft-realtime applications incredibly well with a simple model of concurrency and primitives that encourage thinking about fault tolerance -- did I mention functional programming?

{{< youtube bo5WL5IQAd0 >}}

This covers some wide ranging and complex important topics let's take a peek under the covers of what we say "yes" to when we want shared
memory concurrency -- spoiler it's hard, but alas we're rebels and rust has _fearless concurrency_ right?:

![Danger](/crit.png)

## Shaping performance constraints

It's a worrying premise to write programs in an environment that doesn't have any kind of shared state. In a database for example, you can't just go around copying everything. In the erlang/elixir ecosystem this is solved by leveraging erlang term storage(ets), and it's a key component of the distributed persistent database mnesia all built aware of the language runtime.

>It would be very difficult, if not impossible to implement ETS purely in Erlang with similar performance. Due to its reliance on mutable data, the functionality of ETS tables is very expensive to model in a functional programming language like Erlang. [1]

Before we get into the bells and whistles of it all, what is it at its core? Conceputally a key-value store seems simple.
What you want to model is an abstract interface that can store _schemaless_ data and retrieve it fast, essentially a map/dictionary/associative array abstract data type:

```go
type Table[Key comparable, Value any] interface {
  Read(Key) (Value, error)
  Write(Key, Value)
  Delete(Key)
  In(Key) bool
}
```

In terms of an api for this `Table`, we're looking to define the instance options `bag`, `duplicate_bag`, `set` and `ordered_set`.
If familiar with `table relations` in relational databases, think of the key-value mapping like so:

1. one to one(1:1) = `set`
2. one to one(but with order) = `ordered_set`
3. one to many(1:N) = `bag`
4. many to many(N:N) `duplicate_bag`

These in theory allow us to model all sorts of interesting properties like _referential integrity_ - a relationship between two or more tables but we'll get to that _later_. For now, you might be thinking why not implement this by just throwing a hashmap underneath and that works for types `set`, `bag` and `duplicate_bag`. Infact hashmaps are ubiquitious [4] [5] [6] and contain excellent properties especially when the data set fits in working memory, however most implementations in standard libraries are not thread safe. CPU cores need to synchronize data access to avoid corrupting data or reading inconsistent or stale data.

In rust - sharing an `std::collections::hash_map::HashMap` requires wrapping it in two things:

1. an atomic reference count `Arc<T>`
2. a mutex or some other sync mechanism because the type does not impl `Send` & `Sync`

If your program and data only has to exist within a single thread of execution that's great, but _web servers_ tend to need to handle _concurrent_ data access. Practical examples of this are caches, rate limiting middleware, session storage, distributed config, simple message queues etc

Let's wrap it in a mutex from go's std lib's `sync` package:

```go
type Map[K string, V any] struct {
 sync.Mutex
 Data map[K]V
}
```

To `Read` and `Write` we must acquire `*Map.Lock()` and release `*Map.Unlock()`. This works, up to a point --
but we can do better! We're trying to build a _general purpose_ data store for
key-value data. Global Mutexes are a good solution but you tend to encounter inefficiencies like _lock contention_ on higher values of R/W data access, especially when your hardware can parallelize access when the underlying memory region's slots are partioned perhaps due to hashing across independent memory regions.

One clever way of getting around this is by using an advanced concurrency technique called fine-grained locking, the general idea is instead of a global mutex we serialise access to specific partitions[1]:

```go
type Map[K string, V any] struct {
 Data  map[K]V
 locks []*sync.Mutex
 global sync.Mutex
}
```

This is much more complex but can be more write performant but suffer slightly slower reads. This bottleneck of locks and linearization is the reason databases like postgres and mysql have Multi Version Concurrency Control(MVCC) semantics for pushing reads and writes further using transactions and isolation levels. We'll come back to exploring these fun problems and the tradeoffs and ask the question are locks truely necessary?

Next, we'd like to be able to store both ordered and unordered key value data, hash maps store unordered data so this calls for some sort of additional data structure with fast ordered `Table` operations for our `ordered_set`. We must define a new interface:

```go
type OrderedTable[Key cmp.Ordered, Value any] interface {
  Read(Key) (Value, error)
  Write(Key, Value)
  Delete(Key)
  In(Key) bool
  Range(Key, Key) []Value
}
```

For a concrete implementation, let's start with the conceptually simplest/fastest* the Binary Search Tree and a global `RWMutex`:

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

Search trees are the "go to" structure for keeping performant ordered data with balanced read/write performance, by ensuring we keep the "search property" we can perform on average operations in `O(logN)` -- if the tree is balanced. Sadly in reality they're bounded by the worst time-complexity of `O(h)` where h is the height of the tree. What that means is if we get unlucky
with the data - searches can devolve into searching a linked-list. That wouldn't do. Here there are many flavors thankfully.

Fan favorites include the classics; an AVL Tree, B-Tree or perhaps an LSM Tree, which all come with spices and even more variety.

In practice we are concerned about much more than order of magnitude choices, we are also interested in how these structures
interact with memory layout, can the data fit in main memory (internal) or is it on disk(external)? is it cache friendly? are the node values blocks of virtual memory or random access? sorting files in a directory is a common example of this problem. What kind of concurrent patterns are enabled? how do they map to our eventual high level API? These questions lead to very different choices in algorithm design.

What exists in the current erlang runtime system? The data structure chosen previously of which we'll be benchmarking against is something called a [Contention Adapting Tree](https://www.erlang.org/blog/the-new-scalable-ets-ordered_set/) [2]. Briefly what's interesting about CA Tree is it dynamically at runtime changes the behaviour and number of locks it holds across the tables it protects depending on nature of contention protecting underneath a sequential ordered data structure such as a treap or AVL Tree.

## Concurrency, Correctness & Going web scale

These days are you a serious software craftsman [if you're not at web scale?](https://www.youtube.com/watch?v=b2F-DItXtZs).

In our undying, unending pursuit to scale systems further and further we spin webs of complexity. [Why? who knows, it's provocative.](https://www.youtube.com/watch?v=RlwlV4hcBac)

Let's put on our scaling cap. Previously we mentioned fine-grained locking as a technique that could lead to better write performance but at the cost of complexity and read performance -- a related application of this technique is called "sharding".

Sharding is a wonderful idea, if one hashmap won't work, let's scale _horizontally_, have you tried two? or perhaps sixteen or thirty two?
Java's `ConcurrentHashMap` and rust's `DashMap` are defacto examples of this. However we need to ask isn't this getting complex? can we still understand the system? most importantly can we guarantee _correctness?_

As it turns out most databases need to ensure certain guarantees with respect to performance, concurrency and correctness and here we discuss the elusive idea of a "transaction".  You've probably heard the acronymn ACID - Atomicity, Consistency, Isolation and Durability. What does that mean for ets? Lucky for us, we can cast away the durability requirement as our data set must fit in working memory(for now). That leaves us with:

- Atomicity
- Consistency
- Isolation

### Atomicity

At the level of hardware what is atomicity? It's a special instruction set.
An example of an interface to this is go's [sync/atomic](https://pkg.go.dev/sync/atomic).
This instruction gives a certain _guarantee_,that you can perform an operation without _side effects_ like another process
peeking a half-baked result. You bake a pie or you don't -- however we're getting ahead of ourselves as this part has to do with _visibility_.

Now here's where we have to be careful. ETS operations are semantically -- **independently atomic**[9].

Every operation such as a read, write or multi_write on a table are atomic for a single process. In the relational model
you have BEGIN, COMMIT & ROLLBACK semantics where you can group multiple write operations and pretend they're a single atomic operation. Mnesia builds upon
ets and supports [grouping multiple writers](https://www.erlang.org/doc/apps/mnesia/mnesia_chap4#atomicity) with [transactions](https://www.erlang.org/doc/man/mnesia#transaction-1) but ets does not.

## Isolation

Isolation is really about how we define the _logical concurrent access rules_ of a `Table`. In ets we have different access modes for processes:

- public: all processes may read or write.
- protected: all process may read but one exclusive writer.
- private: single reader and writer.

Why does this matter? Before it was hinted at why the MVCC paradigm [8] exists -- naive locking hurts all query performance, yet locks are desirable
because they ensure correct logical ordering -- linearizability.

It's worth pausing to consider this for a moment.

Concurrency is a powerful concept, we can take three logically independent events A, B then C -- potentially reorder them by alternating or _interleaving_
their execution's progress and reassemble them as A, B then C -- sequential, nice & correct. Systems must be correct, but not necessarily sequential.

There's a hint of that infamous word here -- a tradeoff, in a concurrent universe performance or correctness pick one? Sadly reality is more complex
and there are different shades on this spectrum that trade one thing by changing the definition of another [the devil is in the details](https://en.wikipedia.org/wiki/Consistency_model).

What to do? Inline with the _more is better_ philosophy of scaling are (read/write) locking groups, have you tried adding more _specialised_ locks? We can seperate our read access from our writes and scale those patterns somewhat independently -- this is the working principle of _snapshot insolation_. The concurrency control works by keeping multiple versions on each write and match transactions to specific version of the database at a checkpoint. In a database like postgres you might be familiar with  row or table level locks such as FOR UPDATE or ACCESS EXCLUSIVE, in mnesia you have similar [locking semantics](https://www.erlang.org/doc/man/mnesia#lock-2).

What does this mean for ets? unlike Mnesia ets has no need for MVCC because it does not model the idea of a "transaction", nor does it have [quorum](https://www.erlang.org/doc/man/mnesia_registry) or [consistency](https://www.erlang.org/doc/man/mnesia#sync_transaction-1) problems, nonetheless the ideas of having reader and writer groups prove useful.

## Consistency

Consistency is a tricky topic. In a way we can think of _referential integrity_ as a consistent property of a database. You define a primary key and a foreign key and specify a logical relationship between entities based on this -- but really you're defining an interface and specifying a contract with an invariant that must be implemented. ETS does not have referential integrity, check constraints or schema validation, it stores/retrieves data agnostic of the kind or shape and enforces a serializable/linearizable api for concurrent reads and writes to every function API.

## The dumpster fire that is garbage collection

So far we haven't really had to worry about garbage collection. We've disscussed reading and writing data to the `Table`, but not deletion.

We know we cannot statically allocate memory for our `Table` because we don't know its contents at compile time and we must do dynamic memory allocation.
What happens when we delete a node in the `Table` or `OrderedTable`?

A brief mention of rust mentioned using atomic reference counts an implementation of the strategy [reference counting](https://doc.rust-lang.org/book/ch15-04-rc.html) and in go where this operation is automatic and opaque to the user we didn't really have to worry about it. The resource allocation strategy is tightly coupled to the programming language and environment we intend our concrete key value implementation to eventually live, so at this point we bid farewall to go and carry on with the intricacies of low-level memory management in rust.

Garbage collection is a complex topic but a brief overview of options are:

- malloc, calloc(), free() and realloc()
- refrence counting
- automatic garbage collection (tracing & mark and sweep etc)
- Custom memory allocation

## A detour for just enough web assembly

tdlr; crash course in just enough webassembly

# Gotta Go Fast

at what cost?

- use of lock free data structures/behaviour across reads - concurrent skip list crash course, why?

intro to lock free techniques[3]

## More complex Types

- conformance and integration with/into the firefly runtime

So far these examples have been somewhat generic but the underlying implementation only allowed simple types a key of type `string` and a value of `int`.
This is intentionally done in order not to distract from other concepts, but if we really want a general key value store we need to allow many types.
In this case we want to allow every type supported by the erlang runtime systems.

## Persistence and Durability

ETS has an alternative implementation call Disk-Based Term Storage -- however to implement it we have to re-examine what durability in ACID means.

Implementing the DETS api

 > disks have relatively long seek times, reflecting how long it takes the desired part of the disk to rotate under the read/write head. Once the head is in the right place, the data moves relatively quickly, and it costs about the same to read a large data block as it does to read a single byte

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
- [4] [Hash Indexes in postgres](https://www.postgresql.org/docs/16/hash-intro.html)
- [5] [Adaptive Hash Index in mysql](https://dev.mysql.com/doc/refman/8.3/en/innodb-adaptive-hash.html)
- [6] [Hstore - key/value datatype in postgres](https://www.postgresql.org/docs/current/hstore.html)
- [7] [Index Locking in postgres](https://www.postgresql.org/docs/current/index-locking.html)
- [8] [MVCC introduction](https://www.postgresql.org/docs/current/mvcc.html)
- [9] [Concurreny in ETS](https://www.erlang.org/doc/man/ets#concurrency)

## Notes
>
> In a reader-writer lock, a read acquisition has to be visible to
writers, so they can wait for the reads to finish before succeeding to take a write lock. One way to implement this is to have
a shared counter that is incremented and decremented atomically
when reading threads are entering and exiting their critical section.

<https://preshing.com/20120612/an-introduction-to-lock-free-programming/>
