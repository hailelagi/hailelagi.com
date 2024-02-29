---
title: "Database Internals: B Tree Basics - Concepts"
date: 2024-02-27T12:44:49+01:00
draft: false
---

⚠️⚠️ WIP: Early Draft ⚠️⚠️

What is a Datastructure: everything is either a contigous block or pointer based.
search techniques: binary search - Olog(N) is powerful.

why is it called a B-Tree? According to one of the co-inventor's [Edward M. McCreight it's short for "balance"](https://vimeo.com/73357851).

## Things to *NOT* think about - (yet)
- Memory allocation: garbage collection and language choice
- The pitfalls of memory: fragmentation & corruption
- pre-mature optimisation (serialisation, network calls etc)
- scope creep (adding fancy concurrency mechanisms - MVCC)
- pre-mature horizontal distribution (sharding, replication, unreliable network and the headaches of distributed systems etc)
- 2-3-Tree, LSM Trees, variants etc.

Onto the How?

## Implementation high level ideas

B-Trees are:
1. In-memory indexes (also used here!)
2. persisted on disk storage organisation. <-- we're here.

Considerations:
- Performance (Access Patterns - everything is about access patterns)
- Correctness & Testing
- Durability (what's a block?, brief overview: buffered IO, mmap, directIO.)

performance big ideas overview:
- why do we want search trees? balancing and order
- going beyond Big-O
- immutability vs immutability
- concurrency
- locality of reference (keep stuff close togther)


## Tools of the Trade
Base your judgement on empirical fact:

- a good debugger or not (dbg etc)
- [flamegraphs](https://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html)
- benchmarking
- tests - unit, integration, fuzzing, proptests, simulations etc

## B Trees
desired properties:
- high fanout (dense trees)
- short height

**Operations Overview**:
- insertion
- access
- deletions

**Split/Merge/Rebalancing**

Performance comes from thinking wholistically about hardware and software together.
Optimizations bear the fruits of pretty benchmarks and complexity.
The first big piece is concurrency and parallelism.

tldr; the hard part about building storage engines is debugging and testing them, old databases are good because time spent in production uncovering (or not uncovering bugs).

In the real world stuff goes wrong(the operating system hides hardware and software faults, but you have to care), data loss is bad and is a big no-no.

### Running in production: Correctness, Testing & Safety
Complexity is **evil** but unavoidable, non-determinism makes you helpless.

testing methodology, loom - concurrency is hard etc:
- How SQLlite is tested: https://www.sqlite.org/testing.html
- Valgrind, Address and Memory Sanitizer
- https://www.cs.utexas.edu/~bornholt/papers/shardstore-sosp21.pdf
- https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/DESIGN.md#safety
- https://apple.github.io/foundationdb/testing.html
- many more...

## Further reading: storage engine architecture
Move towards modularization of database components, decoupled query & execution engine(velox, datafusion etc), storage engine see: [foundationDB](https://apple.github.io/foundationdb/layer-concept.html).

What the heck is going on in your favorite database? _select/biased_ popular deep dives into 
popular storage engines for: postgres/postgres, kubernetes/etcd, mysql/InnoDB, mongodb(WiredTiger):

postgres:
https://postgrespro.com/blog/pgsql/4161516

etcd: https://etcd.io/docs/v3.5/learning/data_model/

innodb: https://dev.mysql.com/doc/refman/8.0/en/innodb-physical-structure.html

mongodb: https://source.wiredtiger.com/11.2.0/arch-btree.html

Things we've come to want/expect out of modern databases:
- Seperation of Storage and Compute: https://clickhouse.com/docs/en/guides/separation-storage-compute
- Multitenancy: https://github.com/neondatabase/neon/blob/main/docs/multitenancy.md
- Distribution/Replication: Availability, Redundancy & Serverless style scale
- DBaaS/Cloud Native Stateful Backend services + Database engine, supabase etc
