---
title: "through the looking glass of block layers"
date: 2024-12-06T17:38:16+01:00
tags: go, filesystems
draft: true
---

The modern computing/data infrastructure is [vast and interesting](https://landscape.cncf.io/). 
Let's explore a tiny slice of it, what happens when you read or write some data persistently on a cloud provider?

Through the looking glass of the strange and worderful world of disk io, let's dive down the block layers and see where data goes
 by writing a filesystem conceptually similar to [google's cloud-storage fuse](https://cloud.google.com/storage/docs/cloud-storage-fuse/overview).

{{% callout %}}
All problems in comp sci. can be solved by another level of indirection.
{{% /callout %}}

Why a filesystem? It's **a fundamental abstraction** we'll use to go spelunking into the lifecycle of a block destined for persistence, 
and of course we'll explore more sophisticated filesystems like **zfs**[^3], **xfs**[^4], **ffs**[^6] and of course **ext4**, 
what are the key ideas and tradeoffs? Like all abstractions we begin not by looking at the implementation we look at the _interfaces_.

## Physical Layer
At the bottom, there must exist some _physical media_ which will hold these bits and bytes we conveniently call a block. It could be an HDD, SSD, [tape](https://aws.amazon.com/storagegateway/vtl/) or something else, [what interface does this physical media present?](https://pages.cs.wisc.edu/~remzi/OSTEP/file-devices.pdf) It's exposed over many _protocols_.

![simplified sketch of file system layering](/sketch_fs.svg)

<p class="subtext" style="font-size: 0.8em; color: #666;">This is a rough sketch for simplicity, I wrote some ascii and let claude render :) </p>


An HDD exposes a "flat" address space to read or write, the smallest atomic unit is a sector (e.g 512-byte block) and flash based 
SSDs expose a unit called a "page" which we can read or write higher level "chunks" [†1] above which are the intricacies of [_drivers_](https://lwn.net/Kernel/LDD3/) (let's assume that part exists) and then the somewhat generic block interfaces:

We have quite a few flavors, a few highlights for linux: 
1. [the kernel block interface](https://linux-kernel-labs.github.io/refs/heads/master/labs/block_device_drivers.html#overview)
2. [ublk](https://spdk.io/doc/ublk.html)
3. [libvirt](https://libvirt.org/storage.html)

As it turns out a filesystem is historically an _internal_ sub-component of the operating system! in kernel/priviledged space. However there's all these interesting _usecases_ for writing all sorts of different _kinds of filesystems_ which make different _design decisions_ at different layers, wouldn't it be nice to not brick yourself mounting some random filesystem I made? How about an _EC2 instance_? or a docker container? now that _virtualisation_ technology is ubiquitous how does that change the interface?

What is a filesystem _really?_ to linux at least it's [the universe and everything else](https://en.wikipedia.org/wiki/Everything_is_a_file), in general it's way of **organising** data and metadata for **access.**

That's a very generic definition.

Filesystems are an incredibly versatile abstraction, applying to [networked/distributed systems](https://static.googleusercontent.com/media/research.google.com/en//archive/gfs-sosp2003.pdf), [process management](https://man7.org/linux/man-pages/man7/cgroups.7.html), [memory management](https://docs.kernel.org/filesystems/tmpfs.html) and what one would normally assume it's for -- persistent storage.

A simple interpretation of a filesystem can be an interface/sub-system that allows the management of blocks of data on disk via metadata known as **files** and **directories.** One layout could be:
```
++++++++++++++++++++++++++++++++++++++++++
+ superblock + inode-table + user data!  +
++++++++++++++++++++++++++++++++++++++++++
```

Some definitions of these data structures:
1. the file (Index-Node(inode) - managing information to find where this block lives, mapping the human readable name to a pointer - and so much more!)
2. The directory (also an inode! `.`, parent `..`, etc)
3. super block - metadata about other metadata (inode count, fs version, etc), this is read by the operating system.

and access methods responding to syscalls: open(), read(), write(), fstat() etc

## Filesystems are composable!

anecdote about stupid thing i did like mounting myself on myself and being locked out:

```bash
haile@ubuntu:/Users/haile$ mount | grep flubber
rawBridge on /temp/flubber-fuse type fuse.rawBridge (rw,nosuid,nodev,relatime,user_id=0,group_id=0,max_read=131072)
rawBridge on /Users/haile/documents/github/flubber type fuse.rawBridge (rw,nosuid,nodev,relatime,user_id=501,group_id=501,max_read=131072)
```

- https://systemd.io/MOUNT_REQUIREMENTS/

[FUSE](https://www.kernel.org/doc/html/next/filesystems/fuse.html)

## In search of POSIX
todo posix?

## POSIX concurrent semantics

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
[^4]: [Scalability in the XFS File System](https://users.soe.ucsc.edu/~sbrandt/290S/xfs.pdf)
[^5]: [fast file system(FFS)](https://dsf.berkeley.edu/cs262/FFS-annotated.pdf)
[^6]: [Understanding Modern Storage APIs](https://atlarge-research.com/pdfs/2022-systor-apis.pdf)
[^7]: [Clarifying Direct I/O Semantics](https://lwn.net/Articles/348739/)

[†1]: Although the smallest unit of a flash is actually a cell, and a write/erase may touch on the block, for simplicity and rough equivalence these are equated.
