---
title: "Things I Want in a Language"
date: 2024-04-08T15:53:36+01:00
draft: false
---

I've never believed in the "one true" programming language. I've learned lots of different languages to questionable levels of proficiency and 
not a single one of them has been "the one". It should be obvious that programming languages are tools and tools do different things well.

You can use a screw driver like a hammer, but you probably shouldn't -- but if you really know what you're doing and have enough time you might 
make even that work out somehow or waste a lot of time learning odd and dangerously unsafe things.

So here's a wish list that I will update whenever it occus to me with features I think are neat and are part of my "perfect language", I don't care how any of these things are supposed to actually work. It's a wish list.

### fine-grained/scoped opt-in/out garbagage collection

Rust does not ship a garbage collector. This isn't a criticism, it's a design choice/trade off. Rust targets systems programmers/programming where the presence of a GC can be a burden -- this is not true for all applications though. A GC removes the need to free memory and programmers are generally more productive in languages with a GC (at least I am and this is about my preferences.). I wish this choice wasn't either/or. You pick a language with a gc or you don't. You want to do some performance criticial section of code? boo hoo go learn something else. I would like to control to what degree the garbage collector is or is not used via some programming interface as a part of the language.

I should be able to do something like rust's `unsafe` block and get the magical properties of manual memory management for sections/sub-sections of code and automatic GC for everything else and it should play nice and make sense.

### Sum Types - Result, Option

Just something, even imaginary one's like  `{:ok, err}` anything but hail marry where is that nil check?

-- Ok Generics, if static: Doesn't have to be this super powerful turing complete system, but we can all learn from go's 180 on the topic.

### Immutability as a default
Self-explainatory

## A standard/community rich library of Immutable Functional Data structures but also mutable variants.
Because concurrency is hard and threads are a reality of programming. Sometimes you want data structures that are mostly performant when used correctly and are easy to reason about across threads.

## A standard/community rich library of concurrency primitives
Do you really want to implement a spinlock? or a lock-free map?

### A pluggable and or customizable runtime

Yes, yes. I know. I use the word "runtime" loosely here. It's historically rare to swap out runtimes. You kind of get one with your language eco-system.
However the design space for runtimes is just like garbage collection, you can get really good and approach an amazing default that works for most problems
but you can always get more out of a runtime by changing the underlying assumptions. 

