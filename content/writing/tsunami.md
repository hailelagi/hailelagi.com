---
title: "Making a Tsunami"
date: 2024-04-04T00:17:18+01:00
draft: true
tags: rust, storage engine
tags: ['archive']
publicDraft: true
---

## Querying

Every good database needs good ergonomics for querying! SQL is popular but is a complex and large standard to implement. Luckily -- [_I don't really have to_](https://arrow.apache.org/datafusion/). Theres lots of syntax for querying key-value stores, redis has one, mongodb has one and even postgres patched in one! There are probably thousands of these kinds of languages -- and 
of course ets has one called a `match_spec` -- If you'd like to see this [ask!](https://github.com/hailelagi/tsunami/issues/4) and if you want to learn about the match spec [leave a thumbs up!](https://github.com/hailelagi/hailelagi.com/issues/1) this version **does not** ship with the match_spec api.

## Future, Maybe Never.

Here's a thought - what if you could query runtime data transaparently across all your erlang nodes? :) 
Wouldn't that be something? Mnesia's asynchronous replication model is leaderless and uses a quorum of writers in a cluster, this has interesting tradeoffs and if it doesn't 
quite fit your problem domain it can be tricky.

## Testing Methodology

- unit testing challenges, tight coupling etc
- conformance with the upstream erts(erlang runtime system) ETS public api and behaviour
- 100% erts TEST SUITE coverage

methodology, coverage, tools, loom, address sanitizer etc insert graphs of benchmark results


## Notes & References


