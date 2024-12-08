---
title: "through the looking glass of block layers"
date: 2024-12-06T17:38:16+01:00
draft: false
---

The modern computing/data infrastructure is [vast and interesting](https://landscape.cncf.io/). 
Let's explore a tiny slice of it, what happens when you read or write some data **persistently** on a modern cloud provider?
Let's conceptually trace our way up the block layers and see where data goes by writing a filesystem ???

{{% callout %}}
All problems in comp sci. can be solved by another level of indirection.
{{% /callout %}}

Why a filesystem? It's **a key abstraction** we'll use to go spelunking into the lifecycle of a block destined for persistence, and of course we'll explore ideas from more sophisticated filesystems like xfs, zfs, ext4 and discuss key ideas and tradeoffs and at the end some practical implications on kubernetes! Like all abstractions we begin not by looking at the implementation we look at the _interfaces_.

## Physical Layer
At the bottom, there must exist some _physical media_ which will hold these bits and bytes we conveniently call a block. It could be an HDD, SSD, [tape](https://aws.amazon.com/storagegateway/vtl/) or something else, [what interface does this physical media present?](https://pages.cs.wisc.edu/~remzi/OSTEP/file-devices.pdf) It's exposed over many _protocols_.

![simplified sketch of file system layering](/sketch_fs.svg)

<p class="subtext" style="font-size: 0.8em; color: #666;">This is a rough sketch for simplicity, I wrote some ascii and let claude render :) </p>


An HDD exposes a "flat" address space to read or write, the smallest atomic unit is a sector (512-byte block) and flash based 
SSDs expose a unit called a "page" which we can read or write higher level "chunks" of. [†1] to create a _file system abstraction_ over this **block interface**, what does it look like?

We have quite a few flavors, a few highlights for linux: 
1. [The internal Kernel Block Device Layer](https://linux-kernel-labs.github.io/refs/heads/master/labs/block_device_drivers.html#overview)
2. [ublk](https://spdk.io/doc/ublk.html)
3. [FUSE](https://www.kernel.org/doc/html/next/filesystems/fuse.html)
4. [libvirt](https://libvirt.org/storage.html)

As it turns out a filesystem is historically a sub-component of the operating system! However there's all these interesting _usecases_ for writing all sorts of different _kinds of filesystems_ which make different _design decisions_ at different layers, wouldn't it be nice to not brick yourself mounting some random filesystem I made? How about an _EC2 instance_? or a docker container? now that _virtualisation_ technology is ubiquitous how does that change the interface? anyway, I'm picking FUSE - file system in userspace back up to filesystems!


### A File system
An interface/sub-system that allows the management of blocks + block devices on disk via abstractons, provides files and directories.
One layout could be:
```
++++++++++++++++++++++++++++++++++++++++++
+ superblock + inode-table + user data!  +
++++++++++++++++++++++++++++++++++++++++++
```

Data structures:
1. the file (Index-Node(INode))
2. The directory (self `.`, parent `..`, etc)
3. access methods: open(), read(), write(), fstat() etc
4. super block - metadata about other metadata (inode count, fs version, etc)

## Design choices/tradeoffs
- Tree vs Array
- Bitmap index vs free list vs Btree
- Indexing non-contiguous layout (pointers vs extents)
- static vs dynamic partitioning
- Block size

### Problems
- Latent sector errors
- Misdirected IO
- Disk corruption (physical media - heat etc)
- Fragmentation

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


## References & Notes
[^1]: [Can Applications Recover from fsync Failures?](https://www.usenix.org/system/files/atc20-rebello.pdf)
[^2]: [Protocol Aware Recovery](https://www.usenix.org/conference/fast18/presentation/alagappan)
[^3]: [End-to-end Data Integrity for File Systems: A ZFS Case Study](https://research.cs.wisc.edu/wind/Publications/zfs-corruption-fast10.pdf)

[†1]: Although the smallest unit of a flash is actually a cell, and a write/erase may touch on the block, for simplicity and rough equivalence these are equated.
