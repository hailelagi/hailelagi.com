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

recursive mounts ie explain what a loopback is. 

Here's an example [from the go-fuse documentation](https://github.com/hanwen/go-fuse/blob/master/example/loopback/main.go)
of what this looks like:

```go
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path"
	"runtime/pprof"
	"syscall"
	"time"

	"github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"
)

func writeMemProfile(fn string, sigs <-chan os.Signal) {
	i := 0
	for range sigs {
		fn := fmt.Sprintf("%s-%d.memprof", fn, i)
		i++

		log.Printf("Writing mem profile to %s\n", fn)
		f, err := os.Create(fn)
		if err != nil {
			log.Printf("Create: %v", err)
			continue
		}
		pprof.WriteHeapProfile(f)
		if err := f.Close(); err != nil {
			log.Printf("close %v", err)
		}
	}
}

func main() {
	log.SetFlags(log.Lmicroseconds)
	// Scans the arg list and sets up flags
	debug := flag.Bool("debug", false, "print debugging messages.")
	other := flag.Bool("allow-other", false, "mount with -o allowother.")
	quiet := flag.Bool("q", false, "quiet")
	ro := flag.Bool("ro", false, "mount read-only")
	directmount := flag.Bool("directmount", false, "try to call the mount syscall instead of executing fusermount")
	directmountstrict := flag.Bool("directmountstrict", false, "like directmount, but don't fall back to fusermount")
	cpuprofile := flag.String("cpuprofile", "", "write cpu profile to this file")
	memprofile := flag.String("memprofile", "", "write memory profile to this file")
	flag.Parse()
	if flag.NArg() < 2 {
		fmt.Printf("usage: %s MOUNTPOINT ORIGINAL\n", path.Base(os.Args[0]))
		fmt.Printf("\noptions:\n")
		flag.PrintDefaults()
		os.Exit(2)
	}
	if *cpuprofile != "" {
		if !*quiet {
			fmt.Printf("Writing cpu profile to %s\n", *cpuprofile)
		}
		f, err := os.Create(*cpuprofile)
		if err != nil {
			fmt.Println(err)
			os.Exit(3)
		}
		pprof.StartCPUProfile(f)
		defer pprof.StopCPUProfile()
	}
	if *memprofile != "" {
		if !*quiet {
			log.Printf("send SIGUSR1 to %d to dump memory profile", os.Getpid())
		}
		profSig := make(chan os.Signal, 1)
		signal.Notify(profSig, syscall.SIGUSR1)
		go writeMemProfile(*memprofile, profSig)
	}
	if *cpuprofile != "" || *memprofile != "" {
		if !*quiet {
			fmt.Printf("Note: You must unmount gracefully, otherwise the profile file(s) will stay empty!\n")
		}
	}

	orig := flag.Arg(1)
	loopbackRoot, err := fs.NewLoopbackRoot(orig)
	if err != nil {
		log.Fatalf("NewLoopbackRoot(%s): %v\n", orig, err)
	}

	sec := time.Second
	opts := &fs.Options{
		// The timeout options are to be compatible with libfuse defaults,
		// making benchmarking easier.
		AttrTimeout:  &sec,
		EntryTimeout: &sec,

		NullPermissions: true, // Leave file permissions on "000" files as-is

		MountOptions: fuse.MountOptions{
			AllowOther:        *other,
			Debug:             *debug,
			DirectMount:       *directmount,
			DirectMountStrict: *directmountstrict,
			FsName:            orig,       // First column in "df -T": original dir
			Name:              "loopback", // Second column in "df -T" will be shown as "fuse." + Name
		},
	}
	if opts.AllowOther {
		// Make the kernel check file permissions for us
		opts.MountOptions.Options = append(opts.MountOptions.Options, "default_permissions")
	}
	if *ro {
		opts.MountOptions.Options = append(opts.MountOptions.Options, "ro")
	}
	// Enable diagnostics logging
	if !*quiet {
		opts.Logger = log.New(os.Stderr, "", 0)
	}
	server, err := fs.Mount(flag.Arg(0), loopbackRoot, opts)
	if err != nil {
		log.Fatalf("Mount fail: %v\n", err)
	}
	if !*quiet {
		fmt.Println("Mounted!")
	}

	c := make(chan os.Signal)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-c
		server.Unmount()
	}()

	server.Wait()
}
```

- https://systemd.io/MOUNT_REQUIREMENTS/

[FUSE](https://www.kernel.org/doc/html/next/filesystems/fuse.html)

## File systems come with great responsibility
crash stop, fail stop, data loss, guarantees? journal fs

## In search of POSIX
todo posix?

## POSIX concurrent/file semantics

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
[^8]: [Exploiting Cloud Object Storage for High-Performance Analytics](https://www.vldb.org/pvldb/vol16/p2769-durner.pdf)

[†1]: Although the smallest unit of a flash is actually a cell, and a write/erase may touch on the block, for simplicity and rough equivalence these are equated.