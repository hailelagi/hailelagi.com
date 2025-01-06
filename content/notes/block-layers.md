---
title: "through the looking glass of blocks"
date: 2024-12-06T17:38:16+01:00
tags: go, filesystems
draft: true
---

The modern computing/data infrastructure is [vast and interesting](https://landscape.cncf.io/). What happens when you read or write some data persistently?

What _really_ lurks in the world of disk IO? what is at the core? how do abstractions like [google's cloud-storage fuse](https://cloud.google.com/storage/docs/cloud-storage-fuse/overview) come to be?

Why a filesystem in the first place? It seems like **a fundamental abstraction**, an idea pervasive to any computer, it's important to appreciate it's an _invention_. What do sophisticated filesystems old and new alike, say **zfs**[^1], **xfs**[^2], **ffs**[^3] really do? why are there so many? what are the _key ideas and design tradeoffs?_ what are the _workloads?_ Like all abstractions we begin not by looking at the implementation we look at the _interfaces_.

## Physical Layer
At the bottom, there must exist some _physical media_ which will hold these bits and bytes we conveniently call a block. It could be an HDD, SSD, [tape](https://aws.amazon.com/storagegateway/vtl/) or something else, [what interface does this physical media present?](https://pages.cs.wisc.edu/~remzi/OSTEP/file-devices.pdf) It's exposed over many _protocols_.

![simplified sketch of file system layering](/sketch_fs.svg)

<p class="subtext" style="font-size: 0.8em; color: #666;"> An important theme here is the _compositional_ almost recursive nature of storage interfaces, this comes up again and again and again. :) </p>

An HDD exposes a "flat" address space to read or write, the smallest atomic unit is a sector (e.g 512-byte block) and flash based SSDs expose a unit called a "page" which we can read or write higher level "chunks" [†1] above which are the intricacies of [_drivers_](https://lwn.net/Kernel/LDD3/) (let's assume that part exists) and then the somewhat generic block interfaces:

Filesystems are software, there are quite a few layers to experiment with, what we need is a block device abstraction, but which one? a few options: 
1. [the (deprecated?) kernel block interface](https://linux-kernel-labs.github.io/refs/heads/master/labs/block_device_drivers.html#overview)
2. [ublk](https://spdk.io/doc/ublk.html)
3. [libvirt](https://libvirt.org/storage.html)
4. [fuse](https://www.kernel.org/doc/html/v6.3/filesystems/fuse.html)
5. [k8's container storage interface](https://github.com/container-storage-interface/spec/blob/master/spec.md)

{{% callout %}}
All problems in comp sci. can be solved by another level of indirection.
{{% /callout %}}

As it turns out a filesystem is historically an _internal_ sub-component of the operating system! in kernel/priviledged space. However there's all these interesting _usecases_ for writing all sorts of different _kinds of filesystems_ which make different _design decisions_ at different layers, wouldn't it be nice to not brick yourself mounting some random filesystem I made? How about an _EC2 instance_? or a docker container? now that _virtualisation_ technology is ubiquitous how does that change the interface?

What is a filesystem _really?_ to linux at least it's [the universe and everything else](https://en.wikipedia.org/wiki/Everything_is_a_file), in general it's way of **organising** data and metadata for **access.**

That's a very generic definition, that doesn't say much.

Filesystems are an incredibly versatile abstraction, applying to networked/distributed systems[^4] [^5], [process management](https://man7.org/linux/man-pages/man7/cgroups.7.html), [memory management](https://docs.kernel.org/filesystems/tmpfs.html) and what one would normally assume it's for -- persistent storage.

A simple (and useful) interpretation of a filesystem is an interface/sub-system that allows the management of blocks of data on disk, managing metadata and exposing the interface of **files** and **directories.** This system needs to be laid out on disk, which is not byte-addressable and therefore requires a bit of thinking about layout, a first approximation could be:

```
++++++++++++++++++++++++++++++++++++++
+ superblock + inodes + data region  +
++++++++++++++++++++++++++++++++++++++
```

Some definitions:
1. **file**

Is really a `struct` called an index-node (inode) - managing information to find where this file's blocks are, it maps the human readable name to a internal pointer(i number), services an external handle/view(the file descriptor `fd`) - and so much more! perhaps laid as some kind of hashmap/table?

2. **directory*

also an inode! the `.`, parent `..` path name `/foo` etc

3. **super block**

A special kind of header stores interesting global metadata (inode count, fs version, etc) this is read by the operating system during "mount" [more on this](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/managing_file_systems/mounting-file-systems_managing-file-systems#the-linux-mount-mechanism_mounting-file-systems)

4. **data region**: the actual data we care about storing!

and access methods responding to the syscalls users care about for actually interacting with their data: open(), read(), write(), fstat() etc

Files and directories are really inodes which can map `hello.txt` in `user/hello`to some arbitrary block location(on disk) `0x88a...` dumped as hex pointed to by an `inumber` and finally to the sector region(assuming an HDD). For example to find the block for `hello.txt`:
```bash
# assuming a unix(ish)
# to retrieve the pagesize
# assume the sector size is 512bytes and a block 4KiB
getconf PAGESIZE

## you can see an inode's inumber via:
ls -i hello.txt

block = (inumber * sizeof(inode_t)) / blockSize;
sector = ((block * blockSize) + inodeStartAddr) / sectorSize;
```

This glosses over a super important bit about how `ls -i` _finds_ the inumber in the first place, more on access methods and path traversal later!

## Filesystems are composable!

A filesystem is software. It compiles down to a binary known as an image, to use this _image_ we need to execute it through `mkfs` a fancy way of registering it with the operating system and `mount` it - producing a visible interface to interact with it via -- yet another filesystem?

Filesystems are an interface and one goal of a good interface is _composability_, no matter how many times I heard it or read about it didn't quite make sense. For example I mounted my fuse filesystem on its self and broke the link to it's parent filesystem, why could I?:

```bash
haile@ubuntu:/Users/haile$ mount | grep flubber
rawBridge on /temp/flubber-fuse type fuse.rawBridge (rw,nosuid,nodev,relatime,user_id=0,group_id=0,max_read=131072)
rawBridge on /Users/haile/documents/github/flubber type fuse.rawBridge (rw,nosuid,nodev,relatime,user_id=501,group_id=501,max_read=131072)
```

As it turns out this is a somewhat reasonable thing to do and is known as a recursive mount or a loopback, here's an example [from the go-fuse documentation](https://github.com/hanwen/go-fuse/blob/master/example/loopback/main.go):
```go

func main() {
	quiet := flag.Bool("q", false, "quiet")
	ro := flag.Bool("ro", false, "mount read-only")
	directmount := flag.Bool("directmount", false, "try to call the mount syscall instead of executing fusermount")
	directmountstrict := flag.Bool("directmountstrict", false, "like directmount, but don't fall back to fusermount")
	flag.Parse()

	sec := time.Second
	opts := &fs.Options{
		AttrTimeout:  &sec,
		EntryTimeout: &sec,
		NullPermissions: true,

		MountOptions: fuse.MountOptions{
			AllowOther:        *other,
			Debug:             *debug,
			DirectMount:       *directmount,
			DirectMountStrict: *directmountstrict,
			FsName:            orig,   
			Name:              "loopback",
		},
	}
	if opts.AllowOther {
		// Make the kernel check file permissions for us
		opts.MountOptions.Options = append(opts.MountOptions.Options, "default_permissions")
	}
	if *ro {
		opts.MountOptions.Options = append(opts.MountOptions.Options, "ro")
	}

	if !*quiet {
		opts.Logger = log.New(os.Stderr, "", 0)
	}
	server, err := fs.Mount(flag.Arg(0), loopbackRoot, opts)

	c := make(chan os.Signal)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-c
		server.Unmount()
	}()

	server.Wait()
}:
```

At every point during the boot <> runtime lifecycle of an operating system(linux at least) there probably exist filesystems which mount themselves on themselves at some **mount point**, as par for course this implies a [root fs](https://systemd.io/MOUNT_REQUIREMENTS/)

## File systems come with great responsibility
An unreasonable semantic guarantee that filesystems and tangentially databases make is to say they'll take your data to disk and won't lose it via some kind of pinky promise like`fsync`, in the face of the real world(tm) which can and does _lose_ data[^4] and sometimes lies about it, alas our software and hardware are trying their best and define models like "crash stop" and "fail stop", this gets doubly hard for large data centers and distributed systems[^6] where data loss isn't just loss, it's a cascade failure mode of corruption. There are of course many things to be done to guard against the troubling world of physical disks, such as magic numbers, checksums and RAID which transparently map logical IO to physical IO for fault-tolerance in a fail-stop model and performance via your preffered mapping (stripping, mirroring & parity.)


### Concurrency Disk IO scheduling/schedulers
- SSTF
- NBF
- SCAN vs C-SCAN (elevator algorithm)
- SPTF

linux: https://wiki.ubuntu.com/Kernel/Reference/IOSchedulers

### Design choices/tradeoffs
- Inode design: b-tree vs bitmap vs linked list
- Concurrency/transactions
- in search of POSIX
- Bitmap index vs free list vs Btree vs log structure
- Indexing non-contiguous layout (multi level pointers vs extents)
- static vs dynamic partitioning
- Block size


## References & Notes
[^1]: [End-to-end Data Integrity for File Systems: A ZFS Case Study](https://research.cs.wisc.edu/wind/Publications/zfs-corruption-fast10.pdf)
[^2]: [Scalability in the XFS File System](https://users.soe.ucsc.edu/~sbrandt/290S/xfs.pdf)
[^3]: [fast file system(FFS)](https://dsf.berkeley.edu/cs262/FFS-annotated.pdf)
[^4]: [Ceph: A Scalable, High-Performance Distributed File System](https://www.usenix.org/legacy/event/osdi06/tech/full_papers/weil/weil.pdf)
[^5]: [Google File System](https://static.googleusercontent.com/media/research.google.com/en//archive/gfs-sosp2003.pdf)
[^6]: [Exploiting Cloud Object Storage for High-Performance Analytics](https://www.vldb.org/pvldb/vol16/p2769-durner.pdf)
[^7]: [Can Applications Recover from fsync Failures?](https://www.usenix.org/system/files/atc20-rebello.pdf)
[^8]: [Protocol Aware Recovery](https://www.usenix.org/conference/fast18/presentation/alagappan)
[^9]: [Why Files If You Have a DBMS?](https://www.cs.cit.tum.de/fileadmin/w00cfj/dis/papers/blob.pdf)

[†1]: Although the smallest unit of a flash is actually a cell, and a write/erase may touch on the block, for simplicity and rough equivalence these are equated.

[†2]: An aside on permissions, user groups and access control lists, I don't  think security will make the cut, but prob worth an aside.

