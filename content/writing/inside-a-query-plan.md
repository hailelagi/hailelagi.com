---
title: "Inside a Query Plan"
date: 2024-10-16T19:05:55+01:00
draft: true
tags: go, sql, query-engines
---

A long time ago, I was building an admin dashboard + service to pull some data out of several postgres databases for analysis. I wrote a bunch of sql queries, displaying stuff, rendering rows etc and a blue button to export some data to csv/excel. Pretty simple, however it broke in staging, the table had alot of records, indexed properly but the queries, were slow, why?

```
psql -U postgres
select count(*) from table1;
select count(*) from table2;
select count(*) from table3;
select count(*) from table4;
select count(*) from table5;
```

oh, _pretty big tables_, lots of them and i guess the queries are doing a lot of "stuff", guess i have to _optimise_ this query, what's it doing anyway? a bit of googling and [staring at the postgres docs](https://www.postgresql.org/docs/current/using-explain.html):

```
explain analyze my_slow_queries;
```

It produced a long series of arcane sounding words and structures the output as a _tree_ of what it's doing, which you can read bottom-up:
```
postgres=# explain analyze select 1 + 1;
                                     QUERY PLAN                                     
------------------------------------------------------------------------------------
 Result  (cost=0.00..0.01 rows=1 width=4) (actual time=0.001..0.012 rows=1 loops=1)
 Planning Time: 0.522 ms
 Execution Time: 0.128 ms
(3 rows)
```

sqlite on the other hand does a curious thing, instead of holding a tree as an internal representation it compiles down to bytecode, which is plenty interesting design space we'll return to many times[^2]:

```
sqlite> explain select 1 + 1;
addr  opcode         p1    p2    p3    p4             p5  comment      
----  -------------  ----  ----  ----  -------------  --  -------------
0     Init           0     4     0                    0   Start at 4
1     Add            2     2     1                    0   r[1]=r[2]+r[2]
2     ResultRow      1     1     0                    0   output=r[1]
3     Halt           0     0     0                    0   
4     Integer        1     2     0                    0   r[2]=1
5     Goto           0     1     0                    0   
```

If reading opcodes isn't something you do for fun:
```
sqlite> explain query plan select 1 + 1;
QUERY PLAN
`--SCAN CONSTANT ROW
```

This is what is referred to as a _query plan_, it's the _output_ of a program, like all programs, it has a rich history, architectural decisions/trade-offs and constraints, this is called a query/execution engine. It takes as input a _query_ typically in a _query language_ here it's SQL and lets you retrieve 'facts' by isolating the how from the underlying storage, this **decoupling** gives many benefits and in [hindsight is obvious](https://en.wikipedia.org/wiki/Data_independence), but this wasn't always so, until someone(s) figured it out: [^1]:
```
postgres=# select 1 + 1;
 ?column? 
----------
        2
(1 row)
```

A query engine needs to do a few things, first it needs to be **_correct_** and **_fast_**. Correctness is an interesting word, and it has a context that's rooted in a two part formalism, called [_relational algebra_](https://en.wikipedia.org/wiki/Relational_algebra) and **relational calculus.** We're interested in how the first formalism describes a number of operations on a _unordered collection_ of sets:

- select
- projection
- union
- intersection
- difference
- product(cross product)
- join
- division(*)

and a few useful modern extensions, like sorting, windows, aggregates etc.

These define _logical operations_, but we still need some kind of _syntax_ for these operations, enter SQL, or was it SEQUEL?

With these concepts in place, what key concepts exists in a modern query-engine? We know **what** a query describes, how does the query **execute**?

Which brings us to feature two -- performance. A historical glance reveals some influential architectural decisions, we've established the need to seperate the _logical_ what of a query from the _physical_ what the query finds, we've seen the basics of an influential model for reasoning about operations and discovered how syntax is layered, now we head into the weird world of execution.

An influential modern design is the **volcano model**[^3], a popular idea for defining _execution semantics_ of a query and on the other hand the **Morsel-Driven model**[^4] some say is [the fastest table sort in the west](https://duckdb.org/2021/08/27/external-sorting.html).

To understand these ideas we need to take a step back, and look at the **problems** they're addressing, programs are written for computers, and the question is deceptively simple, how do you leverage all the ways a computer allows you to be fast? how do you take a program, any program, and run it across **multiple cores** and leverage hardware advances that run in data centers and modern computers?

How do you _distribute_ this model when the dataset is beyond one computer? Difficult important questions, but we're not ready to answer them yet. 

[^1]: [System R](https://www.seas.upenn.edu/~zives/cis650/papers/System-R.PDF)
[^2]: [Everything You Always Wanted to Know About
Compiled and Vectorized Queries But Were Afraid to Ask](https://www.vldb.org/pvldb/vol11/p2209-kersten.pdf)
[^3]: [Volcano-An Extensible and Parallel Query Evaluation System](https://paperhub.s3.amazonaws.com/dace52a42c07f7f8348b08dc2b186061.pdf)
[^4]: [Morsel-Driven Parallelism: A NUMA-Aware Query
Evaluation Framework for the Many-Core Age](https://db.in.tum.de/~leis/papers/morsels.pdf)
