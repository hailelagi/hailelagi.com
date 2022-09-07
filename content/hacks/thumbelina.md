---
title: 'Thumbelina'
date: 2022-09-07T14:24:32+01:00
draft: false
tags: elixir, rust
recommend: true
---

This is my first entry in a new series called "hacks". Technical demos for the random junk I build.
Thumbelina is an experiment in _extending_ elixir.

> Rust backed erlang NIF for image processing.
>
> -- <cite>[thumbelina's readme](https://github.com/hailelagi/thumbelina/blob/main/README.md)</cite>

Thumbelina tries to be a lazy, ~~distributed~~, data-pipeline processor library. 

The most popular example of this kind of library(NIF) is discord's
[SortedSet](https://github.com/discord/sorted_set_nif), the 
[blog post](https://discord.com/blog/using-rust-to-scale-elixir-for-11-million-concurrent-users) 
is also an excellent resource for the curious, although it extends elixir/erlang in a different way, improving 
mutable shared data access/writes across processes. See features/demo for production ready libraries that target a 
similar feature set.

### Mechanisms
One approach to using programs written in other languages is opening a `Port`, mogrify for example leverages `System.cmd`,
which uses a unix pipe to communicate with the ImageMagick binary via streams of bytes.

Or to use the same mechanism and implement the functionality yourself in C/C++ and (de)serialize, running in the VM, 
known as "linked-in drivers" or as a "hidden node" via a network pipe such as a TCP socket.

If you're generally interested in how to do this yourself, this is a [great introduction](https://www.theerlangelist.com/article/outside_elixir).

### Overview
A Natively Implemented Function(NIF) however runs in a scheduler thread in the BEAM by default, these are expected to be
pre-emptively scheduled quickly and are appropriate for `synchronous` operations such as short performance sensitive 
computations and custom data structures. Implementing a NIF is a little dangerous, see the `README.md` 
for details on pitfalls.

Getting this right at the systems level, requires providing custom concurrency synchronisation and yielding!

Thumbelina uses a yielding mechanism by default implemented in the beam, for data beyond a specified limit or where the 
image bytes cannot be chunked, a dirty NIF thread is spawned to handle CPU bound processing.

### Features/Demo
phoenix server - https://thumbelina.fly.dev/

Thumbelina can be used to run a [distributed global image service](https://fly.io/docs/app-guides/run-a-global-image-service/),
cluster with elixir, underneath it uses `image-rs`, alternative libraries like:
- https://github.com/h2non/imaginary
- https://github.com/imazen/imageflow (with the elixir binding)
- https://github.com/akash-akya/vix

Elixir/Erlang gives you superpowers when it comes to distributed workloads, giving you access to incredible abstractions
that would simply be either too hard or take too long to implement in any other language.

### Going foward
Eventually it is likely possible to distribute the workload across erlang/elixir nodes. If you've found a bug,
or this is something you'd like to see please open an [issue ;)](https://github.com/hailelagi/thumbelina/issues).
