---
title: "DIY an LSM Tree"
date: 2024-04-22T18:11:52+01:00
draft: false
tags: database internals, bookclub
---

day 1 personal notes from LSM in a week, basic components:

- memtable
- SSTable
- WAL

## a memtable

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


day 2:

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

