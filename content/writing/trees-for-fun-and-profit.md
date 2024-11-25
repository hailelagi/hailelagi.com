---
title: "Trees for Fun and Profit"
date: 2024-08-15T08:27:22+01:00
tags: go, rust, storage-engine
draft: true
---

Key-value storage engines form an important core of many systems, a particular curious case is one designed for use in a language designed for soft-realtime applications. 
This is a deep dive into the internal data structures of an in-memory storage engine called erlang term storage(ets) in the runtime standard library of the BEAM - 
erlang/elixir's virtual machine, at the end, we'll take home an alternative design, that's as performant? and maybe an understanding of why this is plausible?

{{< toc >}}

## Setting the stage

Erlang and elixir are functional programming languages and therefore tend to avoid side effects via immutability. It's a worrying premise to write programs in an environment 
that doesn't have any kind of shared state: it seems wasteful and slow to just go around copying all your data structures †[^1]. In the erlang/elixir ecosystem this is solved by 
leveraging erlang term storage a key/value in-memory database and it's a key component of the distributed persistent database mnesia.

>It would be very difficult, if not impossible to implement ETS purely in Erlang with similar performance. Due to its reliance on mutable data, the functionality of ETS tables 
is very expensive to model in a functional programming language like Erlang. [^2]

Here's Joe Armstrong explaining why writing correct, fast, well-tested, concurrent/parallel and distributed programs on modern CPUs is complex and difficult and why erlang/elixir
is appealing, it comes with a concurrent/parallel garbage collector (no global GC pauses, **low-latency by default**), a **shared nothing** runtime that's **multi-core by default**,
scales I/O bound soft realtime applications incredibly well with a simple model of concurrency that eliminates data races, **location transparency** across a cluster and primitives 
that encourage thinking about fault tolerance and reliability -- did I mention functional programming?

{{< youtube bo5WL5IQAd0 >}}

Sadly though, this locks you into a serialized message passing concurrency model, let's cover some wide ranging and complex important topics, by taking a peek under the covers of 
what we say "yes" to when we want _shared memory concurrency._ Joe's advice is let a small group muck about with these gnarly problems and produce nice clean abstractions 
like the [process model](https://www.erlang.org/doc/reference_manual/processes).

Go and rust both have mutable state, rust sells itself on the basis of memory safety and [fearless concurrency](https://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html),
go on simplicity, fast and easy concurrency. Perhaps go would be a simpler and more practical choice? Simple is better? maybe let's start there.

![Danger](/crit.png)

## Shaping constraints

Conceputally a mutable key-value store seems simple. What you want to model is an abstract interface that can store _schemaless_ data (strings, integers, arrays -- anything) and retrieve it fast, essentially a map/dictionary/associative array abstract data type. Let's see an interface example `KVStore` in go:

```go
type KVStore[Key comparable, Value any] interface {
  Get(Key) (Value, error)
  Put(Key, Value) error
  Delete(Key) error
  In(Key) bool
}
```

We also want flexible **data modelling** options to pass for this `KVStore`, we're looking to define the instance options **`bag`**, **`duplicate_bag`**, **`set`** and **`ordered_set`**, we desire:

- a `bag` of elements of unique keys to many values.
- an unordered `set` of unique elements.
- an `ordered_set` of unique elements.
- a `duplicate_bag` of elements with keys and values that multi-map between them.

Why not implement this by just throwing a concrete hashmap datastructure underneath? that works for the semantics of types `set`, `bag` and `duplicate_bag` -- point queries.
 Infact hashmaps are ubiquitious [^4] [^5] [^6] and contain many excellent algorithmic properties, especially when the data set fits in working memory. However most implementations
  in standard libraries are not thread safe. Programs need to synchronize data access to avoid corrupting memory or reading inconsistent or stale data. In rust, the easiest way you
   can share a `HashMap` across threads is by wrapping it in two things:

1. the atomic reference count smart pointer `Arc<T>`
2. a mutex or some other synchronization mechanism on the critical section because the type does not impl `Send` & `Sync`

Storage engines need to handle _concurrent_ and even better yet _parallel_ and hopefully yet `SIMD` optimised data access.
Let's do the simple thing first, let's guard/wrap our shiny conceptual key/value store's concrete implementation in a big old giant mutex from go's std lib's `sync` package:

```go
type Map[Key any, Value any] struct {
 sync.Mutex
 Data map[Key]Value
}
```

To `Read` and `Write` we must acquire `*Map.Lock()` and release `*Map.Unlock()`. This works, up to a point --
but we can do better! We're trying to build a _general purpose_ data store for
key-value data. Global mutexes are a practical solution but you tend to encounter inefficiencies like _lock contention_ on higher values of R/W data access, especially with segregated memory where the memory region's slots are partitioned across independent memory slots and maybe cores?

One way to leverage this property of partitions is sharding, if one hashmap won't work, let's scale _horizontally_, have you tried two? or perhaps sixteen or thirty two? Java's ConcurrentHashMap` and rust's `DashMap` are great examples of this, careful with your hashing algorithm though! 

A well-known technique in database literature is called fine-grained locking or latching, the general idea is instead of a global mutex we serialise access to specific 'levels', the 
high-level idea being we want to seperate read access from write access choosing the smallest possible critical sections[^3]:

```go
type Map[K any, V any] struct {
 Data  map[K]V
 locks []*sync.Mutex
 global sync.Mutex // why this exists
 // is left to the imaginative and curious
 // hint: what happens during a rehash/growth
 // of linear or chain addressing ?
}
```

This [naive implementation](https://github.com/hailelagi/porcupine/blob/main/porcupine/fine-map.go#L43) adds some complexity, however we gain write throughput but pay the cost of acquiring and releasing two locks on some operations, perhaps a reader-writer lock? [something more sophisticated?](https://github.com/efficient/libcuckoo)

Next, we'd like to be able to store both ordered and unordered key value data, hash maps store unordered data so this calls for some sort of additional data structure with fast 
ordered `KVStore` operations for our `ordered_set`. We must define a new interface:

```go
type OrderedKVStore[Key constraints.Ordered, Value any] interface {
  Get(Key) (Value, error)
  Put(Key, Value) error
  Delete(Key) error
  In(Key) bool
  Range(Key, Key) ([]Value, error)
}
```

For the data structure, let's start with the conceptually simplest/fastest* [a Binary Search Tree](https://github.com/hailelagi/porcupine/blob/main/porcupine/bst.go) 
protected by a global `RWMutex`:

```go
type BST[Key constraints.Ordered, Value any] struct {
	root *BSTNode[Key, Value]
	sync.RWMutex
}

type BSTNode[Key constraints.Ordered, Value any] struct {
	key   Key
	value Value

	left  *BSTNode[Key, Value]
	right *BSTNode[Key, Value]
}
```

Search trees are the "go to" structure for keeping performant ordered data with balanced read/write performance, by ensuring we keep the "search property" we can perform on 
average operations in `O(logN)` -- if the tree is balanced. Sadly in reality they're bounded by the worst time-complexity of `O(h)` where h is the height of the tree. 
What that means is if we get unlucky with the data - searches can devolve into searching a linked-list. That wouldn't do. Here there are many flavors thankfully.

Cult classics include; an AVL Tree, Red-Black tree, B-Tree or perhaps an LSM Tree, which all come with spices and even more variety.

Here we are concerned about much more than order of magnitude choices ultimately, we are also interested in how these structures
interact with memory layout, can the data fit in main memory (internal) or is it on disk(external)? is it cache friendly? are the node values blocks of virtual memory(pages) 
fetched from disk? or random access? What kind of concurrent patterns are enabled? are we 
in a garbage collected environment? how do they map to our eventual high level API? These questions lead to very different choices in algorithm design and optimisations.

It's clear we're at a language cross roads, it would be more time consuming and require greater skill than I possess but not impossible to express this in go, we need precise control of memory, performance is a target, garbage collection unpredictable, it must be embedded in a runtime/vm.

The familiar limited set of languages is known: C, C++. I like rust, and have been learning it for awhile, but here we must  be careful to **not muck about** [with rust's ownership rules](https://eli.thegreenplace.net/2021/rust-data-structures-with-circular-references/), 
if the tree [gets cyclic](https://marabos.nl/atomics/building-arc.html#weak-pointers), writing asynchronous collections in rust is difficult, but not impossible, just be really, really careful.

The blessing and curse is there is no garbage collector, and the ownership model neatly assumes dataflow is a [sub-structural](https://en.wikipedia.org/wiki/Substructural_type_system), one-way/fork/join "tree-like" flow, bi-drectional trees, causality graphs and [linkedlists are anything but](https://rust-unofficial.github.io/too-many-lists/), with low-level concurrency into the mix you're in for [dark mystical arts](https://en.wikipedia.org/wiki/ABA_problem).

A binary search tree node can be represented with an `Option<Box<Node<T>>>`. However `Box` has single ownership.
How are we to represent bi-directional data flow? or changing ownership and relocation as one does when balancing? how do we take this binary search tree and transmogrify it into a cool data structure like an avl or red-black tree?
We've gotta break all the compiler rules.

A sane way of of getting around this is by using a `Vec<u8>` of "pointers" or "page ids" and [implementing "arenas"](https://manishearth.github.io/blog/2021/03/15/arenas-in-rust/) or some such strange incantation.

B-Trees have  historically predominated the discussion on persistent/on-disk data structures, these days it battles with the LSM and some say it's winning in the cloud with tiered storage and write optimised workloads. How about in DRAM? How do we go fast?

![Danger](/Speed_Racer_behind_the_wheel.webp)

What is ets? at the heart of its ~10k lines of C code is two data structures a [hash map](https://github.com/erlang/otp/blob/maint/erts/emulator/beam/erl_db_hash.c), and [an ordered tree](https://github.com/erlang/otp/blob/maint/erts/emulator/beam/erl_db_tree.c), with a little query language as a wrapper. The tree is basically an AVL Tree + a CA Tree(more on this shortly) for the [ordered api](https://www.erlang.org/blog/the-new-scalable-ets-ordered_set/) and a linear addressed hashmap.

ETS hashmaps are amortized O(1) access, insertions and deletions. It's a concurrent linear hashmap with [fine-grained rw-locks](https://github.com/erlang/otp/blob/maint/erts/emulator/beam/erl_db_hash.c#L35), [lockeless atomic operations](https://github.com/erlang/otp/blob/maint/erts/emulator/beam/erl_db_hash.c#L133) and lots of interesting optimisations.


A [Contention Adapting Tree](https://www.erlang.org/blog/the-new-scalable-ets-ordered_set/)[^3] is interesting because it dynamically at runtime changes the behaviour and number of locks it holds depending on nature of contention protecting underneath a sequential ordered data structure such as a treap or AVL Tree. A popular in-memory state of the art data structure is the ARTful index, how do the two stack up? Let's find out!

## Indexing is an artform

## Being a good neighbour

Memory access is an abstraction, an `O(1)` operation is too high level a view, let's peel it back. The model of memory as a flat, never-ending, slab of memory, where access is free, fast and  a pointer hop away as opposed to going to disk or going over the wire and all you really have to do is malloc/free and voila memory appears **is a famous illusion**. We require a different lens -- a lens of mechanical sympathy, to truly leverage fast multi-core concurrency.

What _really happens_ when you dynamically need memory? A compiler throws up its hand and decides it [can never be really sure what you mean](https://en.wikipedia.org/wiki/Undecidable_problem), so it exposes an interface and asks you to think carefully about it.

When the need arises... as it often does, you politely ask a kernel for some more memory than what you initially asked for (and sometimes it says no!), and even when it does say yes, it [lies to you about what you're getting](https://en.wikipedia.org/wiki/Virtual_memory) -- and once you get it you have to give it back otherwise memory keeps growing forever - OOM, in a nutshell:
- You need to ask for memory
- You need to keep _track of this memory_ -- it's _lifetime_
- You need to give it back

As it turns out, the hard part is in the middle, keeping track of this forms a [graph](https://en.wikipedia.org/wiki/Graph_(abstract_data_type)) and lots of hardwork has gone into figuring out algorithms to traverse this graph _especially in a concurrent setting_ and packaging it into a nice abstraction -- so nice, it's essentially automatic! Algorithms such as the tracing algorithm // mark and sweep serve this function and much more sophisticated systems exist in real languages like [go's awesome GC](https://tip.golang.org/doc/gc-guide), otherwise:

1. In C everytime we malloc//free **on demand**.
2. RAII + reference counting
3. [No man's land](https://zig.guide/standard-library/allocators/) <-- (we're here, oh no!)

Why is this necessary at all?

The current ETS exists tightly coupled to the internals of the erlang runtime system (erts) -- ETS has its own private memory allocator `erts_db_alloc` and deallocator `erts_db_free` right besides the BEAM virtual machine's global heap in `erl_alloc.c` via `HAlloc`. There's far more going on than we're interested in knowing but the gist is these interfaces know how to allocate memory on a wide variety of architecture targets and environments, we must play nice and share with the host runtime's [garbage collector](https://github.com/erlang/otp/blob/maint/erts/emulator/internal_doc/GarbageCollection.md) which is why it must copy in and out of 'process' address spaces, [yield](https://github.com/erlang/otp/blob/maint/erts/emulator/internal_doc/AutomaticYieldingOfCCode.md) to the [scheduler](../../writing/a-peek-into-the-beam), and manage the lifetime of its memory seperately. This is at the blurry line between C and erlang with the definition of a [built in function(BIF)](http://erlang.org/pipermail/erlang-questions/2009-October/046899.html).

In _hard real-time systems_ this is a table stakes requirement and part of everyday programming life. In rust as mentioned there are several common _implicit_ [RAII inspired](https://en.cppreference.com/w/cpp/language/raii) strategies to manage heap memory allocation all within the ownership/borrowing model and dellocation with the [`Drop`](https://doc.rust-lang.org/std/ops/trait.Drop.html) trait with well known reference counted smart pointers - `Rc`, `Arc` or perhaps directly pushing onto the heap using `Box` and somewhat more esoteric clone/copy on write [`Cow`](https://doc.rust-lang.org/std/borrow/enum.Cow.html) semantics.

## Transactions

All storage engines need to ensure certain guarantees with respect to concurrency and correctness.
 You've probably heard the acronymn ACID - Atomicity, Consistency, Isolation and Durability.
  What does that mean for ets? Lucky for us, we can cast away the durability requirement as our data set must fit in working memory(for now).
That leaves us with:

- Atomicity

At the level of hardware what is atomicity? It's a special instruction set.
An example of an interface to this is go's [sync/atomic](https://pkg.go.dev/sync/atomic).
This instruction gives a certain _guarantee_,that you can perform an operation without _side effects_, in effect linearizable(ish) semantics.

Now here's where we have to be careful. ETS operations are **atomic in a single operation per object/table**[^9].

Every operation such as a read, write or multi_insert on a table are atomic as long as it's within a single function call/table access but _not across multiple_. In optimistic concurrency control a typical mechanism exposed by
row oriented OLTP databases like postgres, you have `BEGIN`, `COMMIT` & `ROLLBACK` semantics where you can **group multiple write operations** and pretend they're a single atomic operation. Mnesia builds upon
ets and supports [grouping multiple writers](https://www.erlang.org/doc/apps/mnesia/mnesia_chap4#atomicity) with [transactions](https://www.erlang.org/doc/man/mnesia#transaction-1) but ets does not. The atomicity contract only extends per single operation on a Table(s) read/write.

- Isolation

Isolation is really about how we define the _logical concurrent access rules_ of a `Table`. In ets we have different access modes for processes:

- public: all processes may read or write.
- protected: all process may read but one exclusive writer.
- private: single reader and writer.

Why does this matter? Before it was hinted at why the MVCC paradigm [^8] exists -- naive locking hurts all query performance, yet locks are desirable
because they ensure correctness properties such as linearizability.

It's worth pausing to consider this for a moment.

Concurrency is a powerful concept, we can take three logically independent events A, B then C -- potentially reorder them by alternating or _interleaving_
their execution's progress and reassemble them as A, B then C -- sequential, nice & correct. Systems must be correct, but not necessarily sequential.

There's a hint of that infamous word here -- a tradeoff, in a concurrent universe performance or correctness pick one? Sadly reality is more complex
and there are different shades on this spectrum that trade one thing by changing the definition of another [the devil is often in the details](https://jepsen.io/consistency/models/). You can tune consistency and change what isolation means -- but that's yet further ahead, this problem is further compounded when you introduce a network call across tables but let's not try that optimisation tempting as it is.

What to do? Inline with the _more is better_ philosophy of scaling an infamous default weakened guarantee of isolation is _snapshot insolation_, the [cannonical isolation level](https://en.wikipedia.org/wiki/Snapshot_isolation). The concurrency control works by keeping multiple versions on each write and matches read transactions to specific version of the database at a checkpoint matching both with a logical but not actual order. In a database like postgres you might be familiar with  row or table level locks such as `FOR UPDATE` or `ACCESS EXCLUSIVE` which give stronger guarantees, in mnesia you have similar [locking semantics](https://www.erlang.org/doc/man/mnesia#lock-2).

What does this mean for ets? unlike Mnesia in :ets has no need for optimistic concurrency control mechanisms such as MVCC because it does not model the idea of a "transaction", nor does it have [quorum](https://www.erlang.org/doc/man/mnesia_registry) problems in a distributed/replicated setting which mask failures in a net-split mutiplying the difficulty and these are out of scope and are the key features mnesia provides.

Instead the time instantiation of a lock acquistion on a single node gives enough information to order reads or writes correctly relatively simpler between interleaving processes and enforcing the invariants `public`, `private` & `protected` leaving it up to the consumer to make informed choices on what concurrent data patterns make sense in the domain problem being solved.

- Consistency

Consistency is a tricky topic. In a way we can think of _referential integrity_ as a consistent property of a database but is it? You define a primary key and a foreign key and specify a logical relationship between entities based on this -- but really you're defining an interface and specifying a contract with an invariant that must be implemented. ETS does not have referential integrity, check constraints or schema validation, it stores/retrieves data agnostic of the kind or shape and enforces a serializable/linearizable api for concurrent reads and writes to every function API.

## Summary & Benchmarks
<!-- here -->

[^1]: [†1] Immutability is not necessarily **always** a performance bottleneck. This is a common critique of functional languages/semantics and more broadly a misunderstanding of the nuances of immutability and its advantages and disadvantages especially with respect to distributed systems, cache coherency and concurrency/parallelism. Mutable state is broadly 'fast' but this doesn't really say anything. Many log-based data structures are immutable? and often AOF + compaction is a great write performance strategy?

[^2]: [On the scalability of the Erlang term storage](http://doi.acm.org/10.1145/2505305.2505308)
[^3]: [More Scalable Ordered Set for ETS Using Adaptation](https://doi.org/10.1145/2633448.2633455)
[^4]: [Hash Indexes in postgres](https://www.postgresql.org/docs/16/hash-intro.html)
[^5]: [Adaptive Hash Index in mysql](https://dev.mysql.com/doc/refman/8.3/en/innodb-adaptive-hash.html)
[^6]: [Hstore - key/value datatype in postgres](https://www.postgresql.org/docs/current/hstore.html)
[^7]: [Index Locking in postgres](https://www.postgresql.org/docs/current/index-locking.html)
[^8]: [Scalable and Robust Latches for Database Systems](https://db.in.tum.de/~boettcher/locking.pdf)
[^8]: [MVCC introduction](https://www.postgresql.org/docs/current/mvcc.html)
[^9]: [Concurreny in ETS](https://www.erlang.org/doc/man/ets#concurrency)
[^10]: [Memory Allocation - Linux](https://www.kernel.org/doc/html/next/core-api/memory-allocation.html#selecting-memory-allocator)
[^11]: [Erlang data types](https://www.erlang.org/doc/reference_manual/data_types)
[^13]: [Lockless Programming Considerations for Xbox 360 and Windows](https://learn.microsoft.com/en-gb/windows/win32/dxtecharts/lockless-programming?redirectedfrom=MSDN)
[^14]: [Learnings from kCTF VRP's 42 Linux kernel exploits submissions](https://security.googleblog.com/2023/06/learnings-from-kctf-vrps-42-linux.html)
[^16]: https://db.in.tum.de/~leis/papers/ART.pdf
[^17]: https://arxiv.org/pdf/2003.07302
[^18]: https://www.cs.umd.edu/~abadi/papers/vldbj-vll.pdf
[^19]: https://disc.bu.edu/papers/fnt23-athanassoulis
[^20]: https://ignite.apache.org/use-cases/in-memory-database.html
[^21]: [scalability](https://www.erlang.org/blog/scalable-ets-counters/)
[^22]: https://www.cidrdb.org/cidr2021/papers/cidr2021_paper21.pdf
[^23]: https://erdani.org/publications/cuj-2004-12.pdf
[^24]: https://cs-people.bu.edu/mathan/publications/fnt23-athanassoulis.pdf
[^25]: https://en.wikipedia.org/wiki/T-tree
[^26]: https://people.freebsd.org/~lstewart/articles/cpumemory.pdf
