---
title: "Database Internals: B Tree Basics - Slides"
date: 2024-03-03T10:52:36+01:00
draft: false
---

generated with: https://www.cs.usfca.edu/~galles/visualization/BPlusTree.html, please feel free to explore!

assumptions:
*non-decreasing order* and *max degree* of 3

## Insertion
Inserting the keys `1` and `2`:

![init](/init.png)


What happens when we insert key `3`? we have our first split:
![split](/split.png)

Let's add key `4` our tree looks unbalanced doesn't it:
![balance](/balance.png)

and now have to "rebalance" our tree with incoming five:
![rebalance](/rebalance.png)

## Search
searching is an Olog(N) operation!

just a reminder this is _really powerful_ if n = 1 billion, dominance:
- lg(n) = 0.030 μs
- f(n) = 1 sec
- nlg(n) = 29.9 sec
- n ** 2 = 31.7 years
- 2 ** n = :/

with a branching factor of 1001 and height 3 can store over one billion keys:
num keys = branching factor ^ height - 1 * branching factor - 1

![search](/search.png)


## Deletion

Let's remove 4.

First we find 4 using binary search, then re-arrange our pointers and rebalance:
![delete](/delete.png)