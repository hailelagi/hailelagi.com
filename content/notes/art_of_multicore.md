---
title: "The art of multicore"
date: 2024-11-04T10:13:39+01:00
draft: true
---

# Introduction
- liveness & safety
- performance often requires looking behind the invisible hand of the memory heirarchy
- concurrent shared counter viz finding primes `volatile counter` + thread local stack copying
- beer cans are conditional variables

## the problems
at the heart are communication and co-ordination problems

- mutual exclusion
- starvation-freedom
- producer-consumer
- the readers-writers problem

> Amdahl’s Law says that even if we manage to parallelize 90% of the solution, but not the remaining 10%, then we end up with a five-fold speedup, but not a ten-fold speedup. 


# Principles
## Mutual Exclusion
Threads are state machines, events are transitions of state.
Time is is an abstracct property independent of the wall clock.
We use the relationship -> precedence.

