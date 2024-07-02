---
title: "Making a Tsunami"
date: 2024-04-04T00:17:18+01:00
draft: true
tags: rust, storage engine
publicDraft: true
recommend: true
---

⚠️⚠️⚠️⚠️
This a WIP draft
⚠️⚠️⚠️⚠️


Building a  [runtime-embeddable](https://en.wikipedia.org/wiki/Embedded_database), in-memory, [key value store](https://en.wikipedia.org/wiki/In-memory_database) for messaging, streaming queries and soft-realtime applications. Main memory databases form 
the core of many platforms and are used for creating leaderboards, caches, pubsub and messaging apps. Popular examples are Redis, Memcached and BerkeleyDB.


## Introduction

Tsunami intends to be a performant and ergonomic _alternative_ key/value store with an intuitive dataframe api capable of querying larger than memory datasets. It can be embeddable with any BEAM compatible language: erlang, elixir, gleam etc and offers a backwards-compatible but different take on the default erlang term storage (`:ets`), if familiar with the elixir ecosystem, it sits somewhere in the middle of explorer and ets itself.

<!-- INSERT GIF DEMO HERE -->

But before that context, here's Joe Armstrong explaining why writing correct, fast, well-tested, concurrent/ parallel and distributed programs on modern CPUs is complex and difficult and why erlang/elixir is appealing, it comes with a concurrent/parallel garbage collector (no global GC pauses, **low-latency by default**), a **shared nothing architecture** runtime that's **multi-core by default**, scales I/O bound soft realtime applications incredibly well with a simple model of concurrency that **eliminates data races** and primitives that encourage thinking about fault tolerance -- did I mention functional programming?

{{< youtube bo5WL5IQAd0 >}}

This covers some wide ranging and complex important topics, let's take a peek under the covers of what we say "yes" to when we want _shared
memory concurrency_ -- spoiler it's hard, Joe's advice is let a small group muck about with these gnarly problems and produce nice clean abstractions 
like the [process model](https://www.erlang.org/doc/reference_manual/processes). However rust sells itself on the basis of memory safety and [fearless concurrency](https://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html), is there a way to combine the two?

![Danger](/crit.png)

## Shaping constraints

It's a worrying premise to write programs in an environment that doesn't have any kind of shared state: it seems wasteful and slow to just go around copying all your data structures †[^1]. In the erlang/elixir ecosystem this is solved by leveraging erlang term storage and it's a key component of the distributed persistent database mnesia all built aware of the language runtime(BEAM).

>It would be very difficult, if not impossible to implement ETS purely in Erlang with similar performance. Due to its reliance on mutable data, the functionality of ETS tables is very expensive to model in a functional programming language like Erlang. [^2]

Before we get into the bells and whistles of it all, what is `ets` at its core? Conceputally a key-value store seems simple.
What you want to model is an abstract interface that can store _schemaless_ data(strings, integers, arrays -- anything) and retrieve it fast, essentially a map/dictionary/associative array abstract data type. Let's see an interface example `Table` in go:

```go
type Table[Key comparable, Value any] interface {
  Get(Key) (Value, error)
  Put(Key, Value) error
  Delete(Key) error
  In(Key) bool
}
```

We also want flexible **data modelling** options to pass for this `Table`, we're looking to define the instance options `bag`, `duplicate_bag`, `set` and `ordered_set`. If familiar with `table relations` aka relational algebra, think of the key-value mapping if you must as:

1. one to one(1-1): is an unordered `set` of elements.
2. one to one(but with order) = is an `ordered_set` of unique elements.
3. one to many(1-N) = is a `bag` of elements of unique keys to many values.
4. many to many(N-N) = is a `duplicate_bag` of elements with keys and values that multi-map between them.

These give use the raw materials(set theory) to model all sorts of interesting properties like _referential integrity_ - a relationship between two or more tables or even express _true relational algebra_ by implementing a _join_ but we'll get to those gnarly problems _later_. For now, you might be thinking why not implement this by just throwing a hashmap underneath and that works for types `set`, `bag` and `duplicate_bag`. Infact hashmaps are ubiquitious [^4] [^5] [^6] and contain many excellent algorithmic properties: among them O(1) access, this is great, especially when the data set fits in working memory. However most implementations in standard libraries are not thread safe. CPU cores need to synchronize data access to avoid corrupting data or reading inconsistent or stale data. In rust - sharing an `std::collections::hash_map::HashMap` requires wrapping it in two things:

1. the atomic reference count smart pointer `Arc<T>`
2. a mutex or some other synchronization mechanism on the critical section because the type does not impl `Send` & `Sync`

If your program and data only has to exist within a single thread of execution that's great, but _web servers_ tend to need to handle _concurrent_ data access. Practical examples of this are caches, rate limiting middleware, session storage, distributed config, simple message queues etc

Let's do the simple thing first, let's guard/wrap our shiny key/value store in a mutex from go's std lib's `sync` package:

```go
type Map[K string, V any] struct {
 sync.Mutex
 Data map[K]V
}
```

To `Read` and `Write` we must acquire `*Map.Lock()` and release `*Map.Unlock()`. This works, up to a point --
but we can do better! We're trying to build a _general purpose_ data store for
key-value data. Global Mutexes are a good solution but you tend to encounter inefficiencies like _lock contention_ on higher values of R/W data access, especially when your hardware can parallelize computation when the memory region's slots are partioned due to hashing across independent memory regions and threads.

The "clever" way of getting around this is by using more concurrency. A technique called fine-grained locking, the general idea is instead of a global mutex we serialise access to specific partitions or multiple levels, the idea being we want to seperate read access from write access[^3]:

```go
type Map[K string, V any] struct {
 Data  map[K]V
 locks []*sync.Mutex
 global sync.Mutex
}
```

This adds some complexity but can be more write performant but suffer slightly slower reads - perhaps a Read-Writer Lock can save us? This bottleneck of locks and linearization is the reason databases have Multi Version Concurrency Control(MVCC) semantics for pushing reads and writes further using transactions and isolation levels. We'll come back to exploring these fun problems and the tradeoffs and ask the question are locks truely necessary?

Next, we'd like to be able to store both ordered and unordered key value data, hash maps store unordered data so this calls for some sort of additional data structure with fast ordered `Table` operations for our `ordered_set`. We must define a new interface:

```go
type OrderedTable[Key cmp.Ordered, Value any] interface {
  Get(Key) (Value, error)
  Put(Key, Value) error
  Delete(Key) error
  In(Key) bool
  Range(Key, Key) ([]Value, error)
}
```

For the data structure, let's start with the conceptually simplest/fastest* [a Binary Search Tree](https://github.com/hailelagi/porcupine/blob/main/porcupine/bst.go) protected by a global `RWMutex`:

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

Search trees are the "go to" structure for keeping performant ordered data with balanced read/write performance, by ensuring we keep the "search property" we can perform on average operations in `O(logN)` -- if the tree is balanced. Sadly in reality they're bounded by the worst time-complexity of `O(h)` where h is the height of the tree. What that means is if we get unlucky
with the data - searches can devolve into searching a linked-list. That wouldn't do. Here there are many flavors thankfully.

Fan favorites include the classics; an AVL Tree, B-Tree or perhaps an LSM Tree, which all come with spices and even more variety.

In practice we are concerned about much more than order of magnitude choices, we are also interested in how these structures
interact with memory layout, can the data fit in main memory (internal) or is it on disk(external)? is it cache friendly? are the node values blocks of virtual memory(pages) fetched from disk? or random access? sorting files in a directory is a simple excercise that illustrates this problem. What kind of concurrent patterns are enabled? how do they map to our eventual high level API? These questions lead to very different choices in algorithm design and optimisations.

What exists in the current erlang runtime system? The data structure chosen previously of which we'll be benchmarking against is something called a [Contention Adapting Tree](https://www.erlang.org/blog/the-new-scalable-ets-ordered_set/) [^3]. Briefly what's interesting about CA Tree is it dynamically at runtime changes the behaviour and number of locks it holds across the tables it protects depending on nature of contention protecting underneath a sequential ordered data structure such as a treap or AVL Tree.

First an experiment with an AVL with weakened properties:
```rust
pub struct WAVLTree<K, V> {
    root: Option<Box<Node<K, V>>>,
}

struct Node<K, V>
where
    K: Send + Sync + cmp::Ord,
    V: Send + Sync,
{
    key: K,
    value: V,
    height: i32,
    left: Option<Box<Node<K, V>>>,
    right: Option<Box<Node<K, V>>>,
}
```

Here we must [muck about with rust's ownership rules](https://eli.thegreenplace.net/2021/rust-data-structures-with-circular-references/). That's orthangonal to the goal though, what interesting properties have we gained and lost?

<!-- TODO: Important. --->
<!-- TODO: Bench read/write, CATree, WAVL Tree, AVL Tree, BST Tree, etc --->

TODO(WIP) here: https://github.com/hailelagi/lettuce

## Concurrency, Correctness & Going web scale

These days are you a serious software craftsman [if you're not at web scale?](https://www.youtube.com/watch?v=b2F-DItXtZs).

In our undying, unending pursuit to scale systems further and further we spin webs of complexity. [Why? No one knows what it means but it's provocative.](https://www.youtube.com/watch?v=RlwlV4hcBac)

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
This instruction gives a certain _guarantee_,that you can perform an operation without _side effects_. You bake a pie or you don't -- however we're getting ahead of ourselves as this part has to do with _visibility_.

Now here's where we have to be careful. ETS operations are **atomic in a single operation per object/table**[^9].

Every operation such as a read, write or multi_insert on a table are atomic as long as it's within a single function call/table access but _not across multiple_. In optimistic concurrency control a typical mechanism exposed by
row oriented OLTP databases like postgres, you have `BEGIN`, `COMMIT` & `ROLLBACK` semantics where you can **group multiple write operations** and pretend they're a single atomic operation. Mnesia builds upon
ets and supports [grouping multiple writers](https://www.erlang.org/doc/apps/mnesia/mnesia_chap4#atomicity) with [transactions](https://www.erlang.org/doc/man/mnesia#transaction-1) but ets does not. The atomicity contract only extends per single operation on a Table(s) read/write.

## Isolation

Isolation is really about how we define the _logical concurrent access rules_ of a `Table`. In ets we have different access modes for processes:

- public: all processes may read or write.
- protected: all process may read but one exclusive writer.
- private: single reader and writer.

Why does this matter? Before it was hinted at why the MVCC paradigm [^8] exists -- naive locking hurts all query performance, yet locks are desirable
because they ensure correct logical ordering -- serializable/linearizability.

It's worth pausing to consider this for a moment.

Concurrency is a powerful concept, we can take three logically independent events A, B then C -- potentially reorder them by alternating or _interleaving_
their execution's progress and reassemble them as A, B then C -- sequential, nice & correct. Systems must be correct, but not necessarily sequential.

There's a hint of that infamous word here -- a tradeoff, in a concurrent universe performance or correctness pick one? Sadly reality is more complex
and there are different shades on this spectrum that trade one thing by changing the definition of another [the devil is in the details](https://en.wikipedia.org/wiki/Consistency_model). You can tune consistency and change what isolation means -- but that's yet further ahead, this problem is further compounded when you introduce a network call across tables but let's not try that optimisation tempting as it is.

What to do? Inline with the _more is better_ philosophy of scaling an infamous default weakened guarantee of isolation is _snapshot insolation_, the [cannonical isolation level](https://en.wikipedia.org/wiki/Snapshot_isolation). The concurrency control works by keeping multiple versions on each write and matches read transactions to specific version of the database at a checkpoint matching both with a logical but not actual order. In a database like postgres you might be familiar with  row or table level locks such as `FOR UPDATE` or `ACCESS EXCLUSIVE` which give stronger guarantees, in mnesia you have similar [locking semantics](https://www.erlang.org/doc/man/mnesia#lock-2).

What does this mean for ets? unlike Mnesia in :ets has no need for optimistic concurrency control mechanisms such as MVCC because it does not model the idea of a "transaction", nor does it have [quorum](https://www.erlang.org/doc/man/mnesia_registry) problems in a distributed/replicated setting which mask failures in a net-split mutiplying the difficulty and these are out of scope and are the key features mnesia provides.

Instead the time instantiation of a lock acquistion on a single node gives enough information to order reads or writes correctly relatively simpler between interleaving processes and enforcing the invariants `public`, `private` & `protected` leaving it up to the consumer to make informed choices on what concurrent data patterns make sense in the domain problem being solved.

## Consistency

Consistency is a tricky topic. In a way we can think of _referential integrity_ as a consistent property of a database but is it? You define a primary key and a foreign key and specify a logical relationship between entities based on this -- but really you're defining an interface and specifying a contract with an invariant that must be implemented. ETS does not have referential integrity, check constraints or schema validation, it stores/retrieves data agnostic of the kind or shape and enforces a serializable/linearizable api for concurrent reads and writes to every function API.

ACID/BASE whatever are strange mental models for a few reasons:

- There's diverging understanding/interpretation of  [what this means](https://stackoverflow.com/questions/3736533/why-doesnt-mongodb-use-fsync/3737121#3737121)
- Although distinct are interwined concepts and are often garbled up in modern systems with distributed systems problems/concepts which further commingle the whole thing, it's a mess.
- These models are supposed to _simplify_ and _abstract_ complex concurrency control but this is doubtful given that perhaps the non-trivial implementation complexity is removed but you still have to understand _how_ databases (esp distributed ones) do this stuff which
[feels terribly leaky](https://www.joelonsoftware.com/2002/11/11/the-law-of-leaky-abstractions/).

## The dumpster fire that is garbage collection

So far we've explored reading and writing data to the `Table` and `OrderedTable` but not deletion, what is deletion?

Deleting data can be thought about as _reclaiming_ and _destroying_. What happens when a program needs memory? If it's _statically known_ it's usually a well understood [let the compiler handle it problem](https://en.wikipedia.org/wiki/Stack-based_memory_allocation). Interfacing with a kernel or raw memory is complex and if a group of smart people can spend alot of time to get it right once and automagically solve it that would be nice indeed. This is the allure of automatic garbage collection. What happens when this model breaks down?

A brief mention of rust mentioned using atomic reference counts an implementation of [automatic reference counting](https://doc.rust-lang.org/book/ch15-04-rc.html) and in go this operation is seemingly automatic and opaque. The resource allocation strategy is tightly coupled to the programming language and environment we intend our concrete key value implementation to eventually live, so at this point we bid farewall to go snippets and explore the problems of lifetimes, alignment & fragementation in rust.

⚠️⚠️ trigger warning `unsafe` rust ahead! ⚠️⚠️

#### Lifetimes, Fragmentation & Alignment

What really happens when you dynamically need memory? The compiler throws up its hand and decides it [can't figure it out](https://en.wikipedia.org/wiki/Undecidable_problem). You do it.

When the need arises... as it often does, you politely ask a kernel for some (and sometimes it says no!), and even when it does say yes, it typically lies to you about what you're getting -- and once you get it, it's this weird stuff that doesn't make sense to your program and eventually... you have to give it back otherwise memory keeps growing forever (B)OOM.

Let's recap:

- You need to ask for memory
- You need to keep _track of this memory_ -- it's _lifetime_
- You need to give it back

As it turns out, the hard part is in the middle, keeping track of this forms a [graph](https://en.wikipedia.org/wiki/Graph_(abstract_data_type)) and lots of hardwork has gone into figuring out algorithms to traverse this graph _especially in a concurrent setting_ and packaging it into a nice abstraction -- so nice, it's essentially automatic! Algorithms such as the tracing algorithm // mark and sweep serve this function and much more sophisticated systems exist in real languages like [go's awesome GC](https://tip.golang.org/doc/gc-guide), otherwise:

1. In C everytime we malloc//free **on demand**. or [Jemalloc.](https://github.com/jemalloc/jemalloc)
2. RAII + reference counting + malloc/jemalloc
3. [DIY](https://zig.guide/standard-library/allocators/) <-- (we're here, oh no!)

Although it's _possible_ to do this in rust, it's [atypical and has all sorts of nuances](https://matklad.github.io/2022/10/06/hard-mode-rust.html). Why are we resorting to such a low, possibly error prone approach?

#### Being a good neighbour
The current ETS exists tightly coupled to the internals of the erlang runtime system (erts) -- ETS has its own private memory allocator `erts_db_alloc` and deallocator `erts_db_free` right on the BEAM virtual machine's heap in `erl_alloc.c` via `HAlloc`. There's far more going on than we're interested in knowing but the gist is these interfaces know how to allocate memory on a wide variety of architecture targets and environments and for the most part resemble C's malloc/free albeit with caveats -- we need to play nice and share with our host runtime, this data-structure is a guest afterall and [must be submissive and yield](https://github.com/erlang/otp/blob/maint/erts/emulator/internal_doc/AutomaticYieldingOfCCode.md) to the all powerful [scheduler](../../writing/a-peek-into-the-beam) as we don't have [BIF](http://erlang.org/pipermail/erlang-questions/2009-October/046899.html) [status](https://www.erlang.org/doc/man/erlang#description).

#### A detour for just enough web assembly

[Webassembly](https://webassembly.org/) is a pretty cool project. The web has four official langauges: html, css, javascript and webassembly. It'd be nice
if you could write rust for your browser no? perhaps you'd like to ship a runnable binary? Games, figma and containers -- without docker. If this key-value store is going to exists agnostic of wheter it happens to run inside webassembly or `x86-64 linux` wouldn't it be nice to virtualize all the things?

#### Making a bad contrived allocator

Other than supporting a target like webassembly, specifying a case-by-case allocation strategy per domain problem can in theory be always more performant[^10] than relying on an automatic garbage collector and in _hard real-time systems_ this is a
table stakes requirement. In rust there are several common _implicit_ [RAII inspired](https://en.cppreference.com/w/cpp/language/raii) strategies to manage heap memory allocation all within the ownership/borrowing model and dellocation with the [`Drop`](https://doc.rust-lang.org/std/ops/trait.Drop.html) trait.

Here we have well known reference counted smart pointers - `Rc`, `Arc` or perhaps directly pushing onto the heap using `Box` and somewhat more esoteric clone on write [`Cow`](https://doc.rust-lang.org/std/borrow/enum.Cow.html) semantics. How does one DIY an allocator?

What do you need? -- it's entirely dependent on the nature of the program!

Here we can model the space required to fit each key-value as a node on a linkedlist. An illustrative example is a [slab allocator](https://en.wikipedia.org/wiki/Slab_allocation) using a [_free list_](https://en.wikipedia.org/wiki/Free_list):

```rust
// statically start with 10 slots of 4096 bytes
const INITIAL_BLOCKS: usize = 10;
// typical page size in bytes on linux x86-64
const DEFAULT_BLOCK_SIZE: usize = 4096;

struct ListNode {
    size: usize,
    next: Option<Box<ListNode>>,
}

pub struct FreeList {
    head: Option<Box<ListNode>>,
}

```

A free list is a linked list where each node is a reference to a contigous block of homogeneous memory unallocated _somewhere_ on the heap. To allocate we specify the underlying initial block size of virtual memory we need, how many blocks and how to align said raw memory:

```rust
impl FreeList {
    pub fn allocate(&mut self, size: usize, align: usize) -> *mut u8 {
      todo()!
    }
}
```

Deallocation is as simple as dereferencing the raw pointer and marking that block as safe for reuse back to the kernel:

```rust
impl FreeList {
    pub fn deallocate(&mut self, ptr: *mut u8, size: usize, align: usize) {
        todo()!
    }
}
```

Typically an implementation of the `GlobalAlloc` trait is where all heap memory comes from this is called the [System allocator](https://doc.rust-lang.org/std/alloc/struct.System.html) in rust which make syscalls like `mmap`, `sbrk` and `brk` and but we don't want to simply throw away the global allocator and talk to the operating system ourselves -- oh goodness no, we'd want to treat it just like `HAlloc` and carve out a region of memory just for this rather than pairing allocations and deallocations everytime we can amortize memory per value stored and simplify some lifetimes. When this is not possible we default to reference counting over a pre-allocated smaller region like `Box`.

We must now consider the `types` of the key and value. In erlang every value is a `Term`[^11] and serializing and deserializing to a specific Term's size and type will also be the responsibility of our Allocator, here we need to be careful as we traverse the cache line that we aren't unnecessarily thrashing the CPU and minimizing context switches and leveraging if any vectorized instruction sets. Luckily there's an awesome 
in-memory format lots of smart folks spent time working on and open sourced called [Arrow](https://arrow.apache.org/) which does just that!

# Gotta Go Fast

![Speed racer 1967](/Speed_Racer_behind_the_wheel.webp)

It might not seem like it,  but we've covered a lot of ground, our key value store's [storage engine](https://en.wikipedia.org/wiki/Database_engine) is almost ready. We have a basis to discuss algorithmic complexity and data structure design, concurrency control with ACID, and a vocabulary to express its bit for bit layout in-memory and access path, however can we do better than lock groups? -- the answer is maybe!

There are two optimisation architectures we haven't discussed yet:

- no shared state, message passing and thread per core pinning[^12]
- lock free/wait free techniques[^13]

Hold on?! Message passing concurrency? Isn't this what elixir/erlang has native support for?

- use of lock free data structures/behaviour across reads - concurrent skip list crash course, why?

## Persistence and Durability

ETS has an alternative implementation call Disk-Based Term Storage -- I have no interest in [wrastling](https://www.youtube.com/watch?v=4HC5GDoixiA) with the complexities of `fsync` but for completeness, in theory however would one implement it? To do that we have to re-examine the assumption of durability. What happens when you write some data to disk?

There are roughly three odd roads/paths on a single node db:

- you write to a buffered read/write stream (you've probably done this, but your writes aren't actually written - only scheduled.)
- you write to virtual memory and negotiate magic with the kernel.
- you ACTUALLY write directly to memory.

Why does the Kernel/OS want you to buffer or write to "fake" memory in the first place? -- it's half performance and half security concerns.

 > disks have relatively long seek times, reflecting how long it takes the desired part of the disk to rotate under the read/write head. Once the head is in the right place, the data moves relatively quickly, and it costs about the same to read a large data block as it does to read a single byte

There's some nuance wheter this is an SSD or HDD, but the gist is it's lipstick on a pig. The data has to travel up, traverse the dragons and castles of memory heirarchy and the weird and wonderful complexity an OS hides -- [syscalls are an abstraction remember?](https://pages.cs.wisc.edu/~remzi/OSFEP/intro-syscall.pdf) Most of the time Buffered IO works and when that's unacceptable, wrangling with mmap is an option -- but [there are caveats](https://www.cidrdb.org/cidr2022/papers/p13-crotty.pdf), so perhaps you definitely want to directly write to memory. It's obviously the "right" choice no? -- but now you start talking about pages, caches, pools, dirty things? and all [sorts of hidden fun goodies](https://15445.courses.cs.cmu.edu/fall2020/notes/05-bufferpool.pdf) that shave off years from your limited life -- [WAL me daddy](https://www.postgresql.org/docs/current/wal-reliability.html).

mmmap for:
- https://ravendb.net/articles/re-are-you-sure-you-want-to-use-mmap-in-your-database-management-system
- https://www.symas.com/post/are-you-sure-you-want-to-use-mmap-in-your-dbms

 No wonder [getting this right is hard](https://wiki.postgresql.org/wiki/Fsync_Errors) and [riddled with ugly bugs](https://danluu.com/fsyncgate/). However there's [renewed hope](https://github.com/axboe/liburing/wiki/io_uring-and-networking-in-2023) in a [shiny new api](https://github.com/axboe/liburing) that's perhaps the future once the [bugs gets ironed out](https://lwn.net/Articles/902466/).

Instead we can ensure that our limited focus is on queries to disk/ram are READ ONLY - so we can freely do mmap magic. Produce nice `Future` streaming access methods with the query engine -- more on that later and _purposefully discourage_ use of the write api to disk: durable, correct, blocking and slow if you try to -- PRs welcome :)

## Querying

Every good database needs good ergonomics for querying! SQL is popular but is a complex and large standard to implement. Luckily -- [_I don't really have to_](https://arrow.apache.org/datafusion/). Theres lots of syntax for querying key-value stores, redis has one, mongodb has one and even postgres patched in one! There are probably thousands of these kinds of languages -- and 
of course ets has one called a `match_spec` -- If you'd like to see this [ask!](https://github.com/hailelagi/tsunami/issues/4) and if you want to learn about the match spec [leave a thumbs up!](https://github.com/hailelagi/hailelagi.com/issues/1) this version **does not** ship with the match_spec api.

## Future, Maybe Never.

Here's a thought - what if you could query runtime data transaparently across all your erlang nodes? :) 
Wouldn't that be something? Mnesia's asynchronous replication model is leaderless and uses a quorum of writers in a cluster, this has interesting tradeoffs and if it doesn't 
quite fit your problem domain it can be tricky.

## Testing Methodology

- unit testing challenges, tight coupling etc
- conformance with the upstream erts(erlang runtime system) ETS public api and behaviour
- 100% erts TEST SUITE coverage

methodology, coverage, tools, loom, address sanitizer etc insert graphs of benchmark results


## Notes & References

[^1]: [†1] Immutability is not necessarily a performance bottleneck. This is a common misconception about functional languages/semantics and more broadly a misunderstanding of the nuances of immutability and its advantages especially with respect to cache coherency and concurrency. Flavors of LSM-Tree based persistent key-value stores or append-only Log-Structured Hash Tables can and have been modelled in erlang. It just so happens _this_ key value store's properties are hard to model entirely with functional semantics.

[^2]: [On the scalability of the Erlang term storage](http://doi.acm.org/10.1145/2505305.2505308)
[^3]: [More Scalable Ordered Set for ETS Using Adaptation](https://doi.org/10.1145/2633448.2633455)
[^4]: [Hash Indexes in postgres](https://www.postgresql.org/docs/16/hash-intro.html)
[^5]: [Adaptive Hash Index in mysql](https://dev.mysql.com/doc/refman/8.3/en/innodb-adaptive-hash.html)
[^6]: [Hstore - key/value datatype in postgres](https://www.postgresql.org/docs/current/hstore.html)
[^7]: [Index Locking in postgres](https://www.postgresql.org/docs/current/index-locking.html)
[^8]: [MVCC introduction](https://www.postgresql.org/docs/current/mvcc.html)
[^9]: [Concurreny in ETS](https://www.erlang.org/doc/man/ets#concurrency)
[^10]: [Memory Allocation - Linux](https://www.kernel.org/doc/html/next/core-api/memory-allocation.html#selecting-memory-allocator)
[^11]: [Erlang data types](https://www.erlang.org/doc/reference_manual/data_types)
[^12]: [Glommio - thread per core](https://github.com/DataDog/glommio)
[^13]: [Lockless Programming Considerations for Xbox 360 and Windows](https://learn.microsoft.com/en-gb/windows/win32/dxtecharts/lockless-programming?redirectedfrom=MSDN)
[^14]: [Learnings from kCTF VRP's 42 Linux kernel exploits submissions](https://security.googleblog.com/2023/06/learnings-from-kctf-vrps-42-linux.html)
