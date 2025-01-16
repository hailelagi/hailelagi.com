---
title: "Garbage collection & Memory Safety for Mortals"
date: 2024-11-09T21:48:27+01:00
draft: true
---

An attempt to explain and intuit garbage collection.

Deleting data can be thought about as two related but distinct operations _reclaiming_ and _destroying_. What happens when a program needs memory? If it's _statically known_ it's usually a well understood [let the compiler handle it problem](https://en.wikipedia.org/wiki/Stack-based_memory_allocation), fit it in the final binary or give clever hints about what to do when the process is loaded by the operating system. Asking for memory and freeing it can get complex, if a group of smart people can spend **alot of time** to get it right once and automagically solve it that would be nice indeed. This is the allure of automatic garbage collection.

 What happens when this model breaks down?

A brief mention of rust mentioned using `Rc/Arc` implementations of [automatic reference counting](https://doc.rust-lang.org/book/ch15-04-rc.html) and in javascript, python and go this operation is seemingly opaque. The resource allocation strategy is tightly coupled to the programming language and environment we intend our concrete key value implementation to eventually live, so at this point we bid farewall to go snippets and explore the problems of lifetimes, alignment & fragmentation in rust.

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


[^1]: [From Buffer Overflows to “Weird Machines” and Theory of Computation](https://www.usenix.org/system/files/login/articles/105516-Bratus.pdf)
[^2]: [Secure by Design: Google’s Perspective on Memory Safety](https://storage.googleapis.com/gweb-research2023-media/pubtools/7665.pdf)


