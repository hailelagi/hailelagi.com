---
title: "Trees for Fun and Profit"
date: 2024-04-30T15:28:28+01:00
draft: true
---

I'm trying to build an in-memory database for messaging, streaming queries and soft-realtime applications. Main memory databases form 
the core of many platforms and are used for creating leaderboards, caches, pubsub and messaging apps. Examples are Redis, Memcached, BerkeleyDB, dragonfly and apache Ignite. They are somewhat similiar to their cousin streaming engines/databases like kafka & redpanda but expose different apis and optimise for different access patterns at different layers.

Tsunami intends to be a performant and ergonomic alternative key/value store with an intuitive dataframe api capable of querying larger than memory datasets. It can be embeddable with any BEAM compatible language.

An alternative to what exactly? The BEAM - erlang's virtual machine, ships an embedded in-memory mutable key/value store called erlang term storage in the runtime standard library. ETS is heavily relied on by many applications and forms the core of many libraries in the ecosystem, such as [Registry](https://hexdocs.pm/elixir/1.12.3/Registry.html) consequently [Phoenix's PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html) and ets's extension mnesia. We're focused on the first part of that claim, performance. How are efficient data structures designed?

What is ets at its storage core? it is two data structures a [hash map](https://github.com/erlang/otp/blob/maint/erts/emulator/beam/erl_db_hash.c), and [a tree](https://github.com/erlang/otp/blob/maint/erts/emulator/beam/erl_db_tree.c). The tree is basically an AVL Tree + a CA Tree(more on this later) for the ordered api and a linear addressed hashmap for the unordered api, since ets [last saw a major update in design](https://www.erlang.org/blog/the-new-scalable-ets-ordered_set/) and [scalability](https://www.erlang.org/blog/scalable-ets-counters/), a lot has changed in the world of efficient concurrent balanced-search trees. Is it possible to find an alternative with desirable tradeoffs?

## A closer look at ets internals
ETS hashmaps have amortized  O(1) access, insertions and deletions. It's a concurrent linear hashmap with [fine-grained rw-locks](https://github.com/erlang/otp/blob/maint/erts/emulator/beam/erl_db_hash.c#L35), [some lockeless atomic operations](https://github.com/erlang/otp/blob/maint/erts/emulator/beam/erl_db_hash.c#L133), adaptive hashing, and too many runtime specific optimisations to mention for managing memory on the heap. What about the AVL + CA tree? for the ordered api?

## Our search begins
We begin exploring proposed alternatives in the paper and a few that seem like really good ideas!


### Design space evaluation - the CA Tree revisited

### Benchmarks


## Miscellaneaous

- https://db.in.tum.de/~leis/papers/ART.pdf
- https://arxiv.org/pdf/2003.07302
- https://www.cs.umd.edu/~abadi/papers/vldbj-vll.pdf
- https://disc.bu.edu/papers/fnt23-athanassoulis
- https://ignite.apache.org/use-cases/in-memory-database.html
