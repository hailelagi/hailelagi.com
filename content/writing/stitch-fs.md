---
title: "Stitching Together Filesystems"
date: 2024-12-06T17:38:16+01:00
tags: go, c, filesystems, fuse, s3
draft: true
---

{{< toc >}}

The modern computing/data infrastructure is [vast and interesting](https://landscape.cncf.io/). What happens when you read or write some data persistently?

What _really_ lurks in the world of disk IO? what is at the core? how do abstractions like [mountpoint-s3](https://github.com/awslabs/mountpoint-s3), [google's cloud-storage fuse](https://cloud.google.com/storage/docs/cloud-storage-fuse/overview) or [ceph-fuse](https://docs.ceph.com/en/reef/man/8/ceph-fuse/) come to be filesystems?

Why a filesystem? It seems like **a fundamental abstraction**, an idea so pervasive to any computer, it's important to appreciate it's an _invention_. What do sophisticated filesystems old and new alike, say **zfs**[^1], **xfs**[^2], **ffs**[^3] and [ext4](https://www.kernel.org/doc/html/v4.20/filesystems/ext4/index.html) really do? why are there so many? what are some of the _key ideas and design tradeoffs?_ what are the _workloads?_ Like all abstractions we begin not by looking at the implementation we look at the _interfaces_.

A quick glance at [flubber a FUSE fs on object storage](https://github.com/hailelagi/flubber):
<script async id="asciicast-569727" src="https://asciinema.org/a/569727.js"></script>

## physical layer
At the bottom, there must exist some _physical media_ which will hold data we conveniently call a 'block'. It could be an HDD, SSD, [tape](https://aws.amazon.com/storagegateway/vtl/) or something else, [what interface does this physical media present?](https://pages.cs.wisc.edu/~remzi/OSTEP/file-devices.pdf) It's exposed over many _protocols_.

![simplified sketch of file system layering](/sketch_fs.svg)

<p class="subtext" style="font-size: 0.8em; color: #666;"> An important theme here is the _compositional_ almost recursive nature of storage interfaces, this comes up again and again and again. :) </p>

A hard disk drive exposes a "flat" address space to read or write, the smallest atomic unit is a sector (e.g 512-byte block) and flash based solid state drives expose a unit called a "page" to which we can issue read or write "commands" [†1] above which are the intricacies of [_drivers_](https://lwn.net/Kernel/LDD3/) (or if you're lucky EC2's generic NVMe interface or a protocol like NVMe express) and then many generic block interfaces, there are quite a few layers to experiment with, what we need is a block device abstraction, but which one?

1. [the linux kernel block interface](https://linux-kernel-labs.github.io/refs/heads/master/labs/block_device_drivers.html#overview)
2. [ublk](https://spdk.io/doc/ublk.html)
3. [libvirt](https://libvirt.org/storage.html)
4. [fuse](https://www.kernel.org/doc/html/v6.3/filesystems/fuse.html)
5. [k8's container storage interface](https://github.com/container-storage-interface/spec/blob/master/spec.md)

(among others)

{{% callout %}}
All problems in computer science can be solved by another level of
indirection, except of course for the problem of too many indirections.
{{% /callout %}}

As it turns out a filesystem is historically an _internal_ sub-component of the operating system! in kernel/priviledged space. However there's all these interesting _usecases_ for writing all sorts of different _kinds of filesystems_ which make different _design decisions_ at different layers, wouldn't it be nice to not brick yourself mounting some random filesystem I made? How about an _EC2 instance_? or a [docker container?](https://docs.docker.com/engine/storage/) today where workloads often run above [hypervisors](https://pages.cs.wisc.edu/~remzi/OSTEP/vmm-intro.pdf) how does that change the interface?

What is a filesystem _really?_ to linux at least it's [the universe and everything else](https://en.wikipedia.org/wiki/Everything_is_a_file), in general it's a way of **organising** data and metadata for **access.**

That's a very generic definition, that doesn't say much.

Filesystems are an incredibly versatile abstraction, applying to networked/distributed systems[^4] [^5], [process management](https://man7.org/linux/man-pages/man7/cgroups.7.html), [memory management](https://docs.kernel.org/filesystems/tmpfs.html) and what one would normally assume it's for -- persistent storage.

A simple (and useful) interpretation of a filesystem is an interface/sub-system that allows the management of blocks of data on disk via metadata and exposing the abstraction of **files** and **directories.** This system needs to be laid out on disk, which is not byte-addressable and therefore requires a bit of thinking about layout, a first approximation of this metadata could be:

```
++++++++++++++++++++++++++++++++++++++
+ superblock + inodes + data region  +
++++++++++++++++++++++++++++++++++++++
```

Some definitions:
1. **file**

Is really a `struct` called an index-node (inode) - managing information to find where this file's blocks are, it maps the human readable name to an internal pointer(i number), services an external handle/view(the file descriptor `fd`) - and so much more! perhaps laid as some kind of hashmap/table?

2. **directory**

also an inode! the `.`, parent `..` path name `/foo` etc

3. **super block**

A special kind of header stores interesting global metadata (inode count, fs version, etc) this is read by the operating system during [mount](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/managing_file_systems/mounting-file-systems_managing-file-systems#the-linux-mount-mechanism_mounting-file-systems)

4. **data region**: the actual data we care about storing!

and access methods responding to the syscalls users care about for actually interacting with their data: `open`, `read`, `write`, `fstat`, `mkdir` etc

Files and directories are really inodes which can map `hello.txt` in `user/hello`to some arbitrary block location(on disk) `0x88a...` dumped as hex pointed to by an `inumber` and finally to the sector region(assuming an HDD). For example to find the block for `hello.txt`:
```bash
# assuming a unix(ish)
# to retrieve the pagesize
# assume the sector size is 512bytes and a block 4KiB
getconf PAGESIZE

# you can see an inode's inumber via:
ls -i hello.txt

# some rudimentary math to figure out block positions
block = (inumber * sizeof(inode_t)) / blockSize;
sector = ((block * blockSize) + inodeStartAddr) / sectorSize;
```

To make this concrete, a small function with some help from `xv6-riscv`, when the filesystem reads from disk given an `inumber`:
```c
void
rinode(uint inum, struct dinode *ip)
{
  char buf[BSIZE];
  uint bn;
  struct dinode *dip;

  bn = IBLOCK(inum, sb);
  rsect(bn, buf);
  dip = ((struct dinode*)buf) + (inum % IPB);
  *ip = *dip;
}
```

This glosses over considering how `ls -i` _finds_ the inumber from **disk** in the first place: and presumes that our files
fit in a 4KiB chunk -- examining `cutecat.gif` on any computer eludes to more going on.

In a nutshell, answering the first question requires traversing from the _root_ **on every single access to resolve hello.txt -> inum 2**:
```c
// Look up and return the inode for a path name.
// If parent != 0, return the inode for the parent and copy the final
// path element into name, which must have room for DIRSIZ bytes.
// Must be called inside a transaction since it calls iput().
static struct inode*
namex(char *path, int nameiparent, char *name)
{
  struct inode *ip, *next;

  if(*path == '/')
    ip = iget(ROOTDEV, ROOTINO);
  else
    ip = idup(myproc()->cwd);

  while((path = skipelem(path, name)) != 0){
    ilock(ip);
    if(ip->type != T_DIR){
      iunlockput(ip);
      return 0;
    }
    if(nameiparent && *path == '\0'){
      // Stop one level early.
      iunlock(ip);
      return ip;
    }
    if((next = dirlookup(ip, name, 0)) == 0){
      iunlockput(ip);
      return 0;
    }
    iunlockput(ip);
    ip = next;
  }
  if(nameiparent){
    iput(ip);
    return 0;
  }
  return ip;
}
```

This _is_ pretty expensive and there's more to be said about designing access methods and traversing inodes efficiently and their interaction with page tables, nevermind transactions. As a play on our re-occurent theme, to represent more space than a page size **we introduce more indirection** in the form of _pointers_, these pointers can come in the form of _extents_ which are in essence a pointer + block len, or multi-level indexes which are "stringed together" pointers to a page with pointers highlighting an important design choice between flexibility vs a space compact representation.

## filesystems are composable!

Filesystems are an interface and one goal of a good interface is _composability_, no matter how many times I heard it or read about it didn't quite make sense. For example when I first mounted an early version of this fuse filesystem, I hadn't implemented directory path traversal, the link to it's parent filesystem was broken:
```bash
haile@ubuntu:/Users/haile/documents/github$ cd flubber
-bash: cd: flubber: Transport endpoint is not connected
```

```bash
haile@ubuntu:/Users/haile$ mount | grep flubber
rawBridge on /temp/flubber-fuse type fuse.rawBridge (rw,nosuid,nodev,relatime,user_id=0,group_id=0,max_read=131072)
rawBridge on /Users/haile/documents/github/flubber type fuse.rawBridge (rw,nosuid,nodev,relatime,user_id=501,group_id=501,max_read=131072)
```

A filesystem is by and large just software. It compiles down to a binary known as an image, to use this _image_ we need to execute it through `mkfs` a fancy way of registering it with the operating system and `mount`, but not all filesystems do the same things. An interesting highlight is a recursive mount, here's an abridged example [from the go-fuse documentation](https://github.com/hanwen/go-fuse/blob/master/example/loopback/main.go) of a loopback filesystem which implements a recursive mounting using the filesystem below it _transparently_ as storage:

```go
func main() {
	loopbackRoot, err := fs.NewLoopbackRoot("/")
	server, err := fs.Mount("/mnt", loopbackRoot, opts)

	c := make(chan os.Signal)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-c
		server.Unmount()
	}()

	server.Wait()
}
```

At every point during the boot <> runtime lifecycle of an operating system(linux at least) there probably exist filesystems which mount themselves on themselves at some **mount point**, as par for course this implies a [root fs](https://systemd.io/MOUNT_REQUIREMENTS/). This compositional nature is often exploited by `copy-on-write` filesystems to cache, decouple and recreate snapshots of filesystem objects, by interacting with the FUSE kernel api, we can mount anything right in userspace! -- more important than _how_ is _why._

## why fuse?
Hopefully it makes sense that file system heirarchies can be built as an interface over whatever you like -- with FUSE or `ublk` it's right in userspace, no need to muck about inside a kernel - that's a scary place, google drive, your [calendar](https://github.com/lvkv/whenfs), a zip archive, [icmp packets](https://en.wikipedia.org/wiki/Internet_Control_Message_Protocol)... it goes on, you are only bounded by imagination -- but should you put it in production?[^7] I don't know, but I know it's possible to do so over object storage and is a natural fit[^6] for certain workloads such as machine learning and analytics: it's cheap, and POSIX access methods are well understood by existing applications, however [beware of latency and compatibility.](https://materializedview.io/p/the-quest-for-a-distributed-posix-fs)

{{% callout %}}
A brief aside on POSIX, there are "popular" syscalls say open, read, write, close, lseek, mkdir etc
but how about the flock, fcntl and the ioctl family? How would locking and transactional semantics work across a network boundary that can fail?
what consistency guarantees?
{{% /callout %}}


## interacting with the fuse protocol

There's an abstraction layer that wasn't mentioned in the first diagram - which sits just below this filesystem application in linux known as the [linux virtual filesystem](https://docs.kernel.org/filesystems/vfs.html) which allows the dispatching of messages in the FUSE protocol somewhat similar to a client-server model:

```
+++++++        +++++++++++         ++++++++++++
+ app +  <-->  + go-fuse + <------> +  daemon +
+++++++        ++++++++++          +++++++++++++
   |                               \ (exchange messages at `/dev/fuse`)
   |                                | (memcpy per msg)
------(user/kernel boundary)------
   |                               +++++++++++++++
+++++++                            ++ fuse kernel +
+ VFS + -------------------------> ++  driver ++++
+++++++                            +++++++++++++++
```

> The High-level FUSE API builds on top of the lowlevel API and allows developers to skip the implementation of the path-to-inode mapping. Therefore, neither inodes nor lookup operations exist in the high-level API,
easing the code development. Instead, all high-level API
methods operate directly on file paths. The high-level
API also handles request interrupts and provides other
convenient features: e.g., developers can use the more
common chown(), chmod(), and truncate()
methods, instead of the lower-level setattr(). File
system developers must decide which API to use, by balancing flexibility vs. development ease.


>  If a user-space file system implements
the write buf() method, then FUSE splices the data
from /dev/fuse and passes the data directly to this
method in a form of the buffer containing a file descriptor. FUSE splices WRITE requests that contain more than
a single page of data. Similar logic applies to replies to
READ requests with more than two pages of data

## write-back caching
The basic write behavior of FUSE is synchronous and only 4KB of data is sent to the user daemon for writing.

## inodes, access methods, concurrency & garbage collection
The command `ls -i hello.txt` helped us find the inode for our file, guided the discovery of file/directory name translation to an inode,
what more can it tell us? A key decision in the design and performance of filesystems is the inode representation, inodes can most commonly be represented by a bitmap, linked-list or a b-tree

todo a contrast with log structured filesystems.

todo RUM ref

## file systems come with great responsibility
A semantic guarantee with a heavy burden that filesystems and tangentially databases make is to say they'll take your data to disk and won't lose it along the way via some kind of mechanisms to force writes to disk, in the face of the real world which can and does _lose_ data[^8] and sometimes lies about it, alas our software and hardware are trying their best and define models like "crash stop" and "fail stop", this gets doubly hard for large data centers and distributed systems[^9] where data loss isn't just loss, it's a cascade failure mode of corruption and headaches. There are of course many things to be done to guard against the troubling world of physical disks, such as magic numbers, checksums and RAID which transparently map logical IO to physical IO for fault-tolerance in a fail-stop model via your preffered mapping (stripping, mirroring & parity.) and of course the [clever rabbit hole of bit flipping repair algorithms](https://transactional.blog/blog/2024-erasure-coding).

Perhaps a more disturbing thought, why a filesystem if you have a database?[^10] [SQLite](https://www.sqlite.org/fasterthanfs.html) seems to agree, as does [Oracle](https://docs.oracle.com/cd/B16351_01/doc/server.102/b14196/asm001.htm#), it's certainly interesting and perhaps it's worth the inherited complexity? why stop at the filesystem? or disk manager? perhaps let's do away with the operating system altogether?[^11] questions for another time :)


{{% callout %}}
Security and access control in whatever form is an important consideration in filesystem design, especially in a distributed context where the network provides a wider surface area of attack than the process boundary. User groups and access control lists are often something worth considering when implementing a filesystem abstraction.
{{% /callout %}}

## transactions and the WAL
todo: a simple commit protocol + wal over object storage.

## references & notes

[†1]: Although the smallest unit of a flash is actually a cell, and a write/erase may touch on the block, for simplicity and rough equivalence these are equated.


[^1]: [End-to-end Data Integrity for File Systems: A ZFS Case Study](https://research.cs.wisc.edu/wind/Publications/zfs-corruption-fast10.pdf)
[^2]: [Scalability in the XFS File System](https://users.soe.ucsc.edu/~sbrandt/290S/xfs.pdf)
[^3]: [fast file system(FFS)](https://dsf.berkeley.edu/cs262/FFS-annotated.pdf)
[^4]: [Ceph: A Scalable, High-Performance Distributed File System](https://www.usenix.org/legacy/event/osdi06/tech/full_papers/weil/weil.pdf)
[^5]: [Google File System](https://static.googleusercontent.com/media/research.google.com/en//archive/gfs-sosp2003.pdf)
[^6]: [Exploiting Cloud Object Storage for High-Performance Analytics](https://www.vldb.org/pvldb/vol16/p2769-durner.pdf)
[^7]: [To FUSE or Not to FUSE: Performance of User-Space File Systems](https://libfuse.github.io/doxygen/fast17-vangoor.pdf)
[^8]: [Can Applications Recover from fsync Failures?](https://www.usenix.org/system/files/atc20-rebello.pdf)
[^9]: [Protocol Aware Recovery](https://www.usenix.org/conference/fast18/presentation/alagappan)
[^10]: [Why Files If You Have a DBMS?](https://www.cs.cit.tum.de/fileadmin/w00cfj/dis/papers/blob.pdf)
[^11]: [Cloud-Native Database Systems and Unikernels: Reimagining OS Abstractions for Modern Hardware](https://www.vldb.org/pvldb/vol17/p2115-leis.pdf)
[^12]: [Don't stack your Log on my Log](https://www.usenix.org/system/files/conference/inflow14/inflow14-yang.pdf)
[^13]: [Designing Access Methods: The RUM Conjecture](https://www.eecs.harvard.edu/~kester/files/rum_conjecture.pdf)
[^14]: [Application Crash Consistency and Performance with CCFS](https://www.usenix.org/system/files/conference/fast17/fast17_pillai.pdf)
