---
title: "Diy an Lsm"
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

reference counting contiguous slices of memory.
2. Arc<&[u8]> see: https://github.com/tokio-rs/bytes

## Interesting links
- https://neon.tech/blog/get-page-at-lsn
- https://neon.tech/blog/architecture-decisions-in-neon
