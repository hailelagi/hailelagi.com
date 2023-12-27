---
title: "Making a Tsunami"
date: 2023-12-23T00:19:58+01:00
draft: false
tags: rust, erts, wasm, k-v store
recommend: false
---

WIP public draft, come back later. <https://github.com/hailelagi/wavl-ets>
Last updated: Wed 27th Dec 2023.

# Introduction

This was one of the first really hard ambitious things I tried to build, but sadly because of
either a lack time, grit or knowledge/skill I just couldn't make meaningful progress.

To be fair - at first it _seemed_ like a simple "good first issue" kind of thing I had no idea what I was opting into, so here's a disclaimer!
We're going to build a type of database! No It's not enough machinery akin to say postgres but there's a fair bit of stuff going on!

Give or take some of the outline:

- some knowledge of programming - you've built a crud app
- an idea of rust's ownership system or exposure to some memory management ala C, C++ or Zig.
- a rough sense of lexical parsing
- some idea about trees and or graph traversal in general
- some concurrency (shared state or message passing)
- Garbage collection in a managed runtime
- Scheduling - how does a runtime handle busy CPU/IO?

Bonus(but not important):

- Atomics/Compare & Swap
- Some exposure to the CPU Cache/cache line movement
- Some knowledge of the BEAM - elixir or erlang (especially :ets)
- Some knowledge of go's syntax/semantics

You've been warned! Grab a coffee or tea and let's scope it out! I'll be using a mixture of go/rust for the examples.

## Experimenting and shaping performance constraints

Before we get into the bells and whistles of it all, what are we _really_ trying to achieve? Conceputally a k-v store is simple.
What you want is to first build an interface that can store k/v paired data in-memory.

```go
type Store[Key comparable, Value any] interface {
  Read(Key) (Value, error)
  Write(Key, Value)
  Delete(Key)
  In(Key) bool
}
```

and you might be thinking why not just throw a hashmap/associate array underneath and that works! If your data access only has to exist
with a single thread that's great, but applications tend to need to handle many _concurrent_ requests - I know! let's wrap it
in a mutex and because I know my read access skews higher than writes maybe I can geta way with:

```go
type LockingMap[K string, V any] struct {
 sync.RWMutex
 Fields map[K]V
}

func (l *LockingMap[string, any]) Read(key string) (any, error) {
  l.RLock()
  defer l.RUnlock()

  value, found := l.Fields[key]

  if !found {
    return value, errors.New("not found")
  }

  return value, nil
}

func (l *LockingMap[string, any]) Write(key string, value any) {
  l.RWMutex.Lock()
  defer l.Unlock()

  l.Fields[key] = value
}
```

This works, up to a point -- but we can do better! We're trying to build a _general purpose_ data store for
key-value data. Mutexes are a good solution but you tend to deal with _lock contention_ on higher values of R/W data access.

This won't do at all! This is the reason databases like postgres and mysql have Multi Version Concurrency Control(MVCC) for accessing data -
another thing - is a hashmap the optimal data structure? Lots of research has gone into (and still goes into this topic!) but if were laying out a data structure for querying data on disk the options seem to be B-Tree(variants) and recently an LSM Tree(variants).

However we don't have to contend with the complexity of `fsync` and durable storage, therefore we can choose a different structure.
Notably we'd like to store both ordered and unordered key value data and this calls for some sort of self balancing data structure.

Let's go with the conceptually simplest on the Binary Search Tree:
```go
type BST[K string, V any] struct {
  // todo
}
```

## Scope/Goals

- conformance with the upstream erts(erlang runtime system) ETS public api and behaviour
- 100% erts TEST SUITE coverage
- use of lock free data structures/behaviour across reads
- conformance and integration with/into the firefly runtime
