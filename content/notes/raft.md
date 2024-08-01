---
title: "Raft"
date: 2024-08-01T15:00:07+01:00
draft: true
---

who doesn't want to build a tiny raft without the overhead of setting up all the networking and test stuff? We just saw a `read-committed` distributed key value store, that's neat. 

It would be best if you have seen: https://thesecretlivesofdata.com/raft/

Or played with the visualisation here: https://raft.github.io/

We want stronger guarantees! -- we want a distributed, linearizable key-value store using the Raft consensus algorithm -- what goes into building one? This is like etcd but bad :)

