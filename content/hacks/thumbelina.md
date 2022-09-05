---
title: 'Thumbelina'
date: 2022-08-04T10:44:33+01:00
draft: true
tags: elixir, rust
recommend: true
---

This is my first entry in a new series called "hacks". Short, technical demos for the random junk I build.
Thumbelina is an experiment in _extending_ elixir.

> Rust backed erlang NIF for image processing.
>
> -- <cite>[thumbelina's readme](https://github.com/hailelagi/thumbelina/blob/main/README.md)</cite>

Thumbelina at its core tries to be a distributed, data-pipeline processing library for image data. 

The most popular example of this kind of library is discord's
[SortedSet](https://github.com/discord/sorted_set_nif), the 
[blog post](https://discord.com/blog/using-rust-to-scale-elixir-for-11-million-concurrent-users) 
is also an excellent resource for the curious, although it extends elixir/erlang in a different way, improving 
shared data access across processes.

If you're generally interested in how to do this yourself, this is a 
[great introduction](https://www.theerlangelist.com/article/outside_elixir).
