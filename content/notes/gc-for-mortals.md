---
title: "Gc for Mortals"
date: 2024-11-09T21:48:27+01:00
draft: true
---

An attempt to explain and intuit garbage collection.


Here we can model the space required to fit each key-value as a node on a linkedlist. An illustrative example is a [slab allocator](https://en.wikipedia.org/wiki/Slab_allocation) using a [_free list_](https://en.wikipedia.org/wiki/Free_list):

```rust
const INITIAL_BLOCKS: usize = 10;
const DEFAULT_BLOCK_SIZE: usize = 4096;

struct ListNode {
    size: AtomicUsize,
    next: Option<Box<ListNode>>,
}

pub struct FreeList {
    size: AtomicUsize,
    head: Option<Box<ListNode>>,
}
```

A free list is a linked list where each node is a reference to a contigous block of homogeneous memory unallocated _somewhere_ on the heap. To allocate we specify the underlying initial block size of virtual memory we need, how many blocks and how to align said raw memory, deallocation is as simple as dereferencing the raw pointer and marking that block as safe for reuse back to the kernel.


Typically an implementation of the `GlobalAlloc` trait is where all heap memory comes from this is called the [System allocator](https://doc.rust-lang.org/std/alloc/struct.System.html) in rust which make syscalls like `mmap`, `sbrk` and `brk` and but we don't want to simply throw away the global allocator and talk to the operating system ourselves -- oh goodness no, we'd want to treat it just like `HAlloc` and carve out a region of memory just for this rather than pairing allocations and deallocations everytime we can amortize memory per value stored and simplify some lifetimes. When this is not possible we default to reference counting over a pre-allocated smaller region like `Box`.
