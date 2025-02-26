---
title: "Storage + SSD = <3"
date: 2024-12-29T02:27:02+01:00
draft: true
---

## Disaggregated storage
why? elasticity(avoid over/under-provisioning), independent scalable resources, cost efficiency(economies of scale),
cloud platforms/data centers are inherently disaggregated. Primitives are pools.

Software disaggregation - aurora, socrates, neon etc how to design a DBMS to run serverless workloads?
Hardware disaggregation - pooling of resources over multi-clouds?

- compute nodes(EC2 etc)
- storage disaggregation (EBS, S3 - SSDs and NVMs) (shared vs shared-nothing)
- memory disaggregation (RDMA, persistent memory (Intel Optane(mostly dead, exists in niche production usecases)), [CXL](https://www.sigops.org/2024/revisiting-distributed-memory-in-the-cxl-era/))

challenges of memory disaggregation adoption:
>  Database systems have been heavily relying on the high speed of random
accesses to main memory to achieve good performance. Memory
disaggregation means that the majority of these accesses now become network communication. Managing remote memory accesses
is thus a key design challenge

> a large disaggregated memory pool can prevent the processing of memory-intensive queries from being spilled to secondary
storage

### For OLTP
aurora + socrates + neon

### For OLAP
snowflake, clickhouse etc

### LSM designs meet SSDs
Page server, Log server et

### Disjoint set optimisations


### LSM nitty

day 1 personal notes from LSM in a week, basic components:

- memtable
- SSTable
- WAL

tunable parameters: compaction and memtable datastructure.

#### a memtable

```rust
pub struct MemTable {
    map: Arc<SkipMap<Bytes, Bytes>>,
    wal: Option<Wal>,
    id: usize,
    approximate_size: Arc<AtomicUsize>,
}
```

1. `skiplist - `crossbeam_skiplist`

see: https://github.com/crossbeam-rs/rfcs/blob/master/text/2018-01-14-skiplist.md
> Regarding performance, a skip list is fundamentally disadvantaged compared to a B-tree. Every node in a skip list is separately allocated on the heap, while a B-tree allocates nodes in large blocks, thus greatly improving cache utilization. The problem of scattered skip list nodes in memory can be somewhat mitigated using custom allocators (by trying to allocate adjacent nodes in a skip list as close as possible in memory), but typically with great difficulty and underwhelming results.

> as soon as we add more threads, contended locking brings a huge penalty on performance.

> poor memory locality re: skip list

reference counting contiguous slices of memory.
2. Arc<&[u8]> see: https://github.com/tokio-rs/bytes

> very important !!!
> Before it can be flushed, the memtable has to be switched: a new memtable is allocated, and it becomes a target for all new writes, while the old one moves to the flushing state. These two steps have to be performed atomically.
> The flushing memtable remains available for reads until its contents are fully flushed. After this, the old memtable is discarded in favor of a newly written disk-resident table, which becomes available for reads.

figuring out the scope for how long what locks should live is tricky...deadlocking yourself is very easy! overly broad locking is also a bad default mode of thought.

> mut memtable -> immutable memtable -> SST what 'current' live read version to serve

> locking policies/tradeoffs, parking_lot::RwLock uses a task-fair locking policy, which avoids reader and writer starvation, whereas the standard library version makes no guarantees.
- https://blog.mozilla.org/nfroyd/2017/03/29/on-mutex-performance-part-1
- https://cs.stackexchange.com/questions/70125/why-are-most-mutex-implementations-unfair
- https://oneapi-src.github.io/oneTBB/main/tbb_userguide/Mutex_Flavors.html


> Usually, storage engines offer a cursor or an iterator to navigate through file contents. This cursor holds the offset of the last consumed data record, can be checked for whether or not iteration has finished, and can be used to retrieve the next data record.

```rust
pub struct MemtableIterator<'a> {
    map: Arc<SkipMap<Bytes, Bytes>>,
    iter: SkipMapRangeIter<'a>,
}
```

## Interesting links/Miscellaneous
- https://neon.tech/blog/get-page-at-lsn
- https://neon.tech/blog/architecture-decisions-in-neon


[^1]: [The Log-Structured Merge-Tree](https://www.cs.umb.edu/~poneil/lsmtree.pdf)
[^2]: [Designing Access Methods: The RUM Conjecture](https://www.eecs.harvard.edu/~kester/files/rum_conjecture.pdf)
[^3]: [Understanding Modern Storage APIs](https://atlarge-research.com/pdfs/2022-systor-apis.pdf)
[^4]: [What Modern NVMe Storage Can Do, And How To Exploit It](https://vldb.org/pvldb/vol16/p2090-haas.pdf)
[^5]: [Clarifying Direct I/O Semantics](https://lwn.net/Articles/348739/)
[^6]: [What Are You Waiting For? Use Coroutines for Asynchronous I/O to Hide I/O Latencies and Maximize the Read Bandwidth!](https://db.in.tum.de/~fent/papers/coroutines.pdf)
[^7]: [The Unwritten Contract of Solid State Drives](https://pages.cs.wisc.edu/~jhe/eurosys17-he.pdf)
[^8]: [Socrates: The New SQL Server in the Cloud](https://www.microsoft.com/en-us/research/uploads/prod/2019/05/socrates.pdf)
[^9]: [Is Scalable OLTP in the Cloud a Solved Problem?](https://www.cidrdb.org/cidr2023/papers/p50-ziegler.pdf)
[^10]: [Disaggregated Database Systems](https://www.cs.purdue.edu/homes/csjgwang/pubs/SIGMOD23_Tutorial_DisaggregatedDB.pdf)
[^11]: [Immutability Changes Everything](https://www.cidrdb.org/cidr2015/Papers/CIDR15_Paper16.pdf?)
[^12]: [Dissecting, Designing, and Optimizing LSM-based Data Stores](https://cs-people.bu.edu/mathan/publications/sigmod22-sarkar-tutorial.pdf)
