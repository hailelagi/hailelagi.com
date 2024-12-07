---
title: "through the looking glass of block layers"
date: 2024-12-06T17:38:16+01:00
draft: true
---

The modern computing/data infrastructure is [vast and interesting](https://landscape.cncf.io/). 
Let's explore a tiny slice of it, what happens when you read or write some data **persistently** on a modern cloud provider?
Let's conceptually trace our way down the block layers and see where data goes by writing a filesystem ???

{{% callout %}}
All problems in comp sci. can be solved by another level of indirection.
{{% /callout %}}

Why a filesystem? It's **a key abstraction** we'll use to go spelunking and of course we'll spin up an ec2 instance + and mount a filesystem for it with s3!


## Hardware
### Hard disk drive
Exposes a "flat" address space to read or write. Smallest atomic unit is a sector (512-byte block).

### SSD
flash/cells.

### Problems
- Latent sector errors
- Misdirected IO
- Disk corruption (physical media - heat etc)


### Disk IO scheduling/schedulers
- SSTF
- NBF
- SCAN vs C-SCAN (elevator algorithm)
- SPTF

linux: https://wiki.ubuntu.com/Kernel/Reference/IOSchedulers

### RAID
transparently map logical IO to physical IO for fault-tolerance(fail-stop model) and performance.
- stripping
- mirroring
- parity

### File system
An OS interface/sub-system that allows the management of blocks + block devices on disk via abstractons:

```
++++++++++++++++++++++++++++++++++++++++++++
+ superblock + inode-table + user data!  +++
++++++++++++++++++++++++++++++++++++++++++++
```

## Data structures:
1. the file (INode + )
2. The directory (self `.`, parent `..`, etc)
3. access methods: open(), read(), write()
4. super block - metadata about other metadata (inode count, fs version, etc)

## Design choices/tradeoffs
- Tree vs Array
- Bitmap index vs free list vs Btree
- Indexing non-contiguous layout (pointers vs extents)
- static vs dynamic partitioning
