---
title: "Inside a Query Plan"
date: 2024-10-16T19:05:55+01:00
draft: true
---

A long time ago, I was building an admin dashboard + service to pull some data out of several postgres databases for analysis.
I wrote a bunch of sql queries, displaying stuff, rendering rows etc and a blue button to export some data to csv/excel. Pretty simple, however it broke in staging, the table had alot of records, indexed properly but the queries, were slow, why?

```
psql -U postgres
select count(*) from table1;
select count(*) from table2;
select count(*) from table3;
select count(*) from table4;
select count(*) from table5;
```

oh, _pretty big tables_, lots of them and ig the queries are doing a lot of stuff, guess i have to _optimise_ this query, what's it doing anyway? a bit of googling and [staring at the postgres docs](https://www.postgresql.org/docs/current/using-explain.html):

```
explain analyze my_shiny_queries;
```

It produced a long series of arcane sounding words and structures the output as a _tree_ which you can read bottom-up:
```
postgres=# explain analyze select 1 + 1;
                                     QUERY PLAN                                     
------------------------------------------------------------------------------------
 Result  (cost=0.00..0.01 rows=1 width=4) (actual time=0.001..0.012 rows=1 loops=1)
 Planning Time: 0.522 ms
 Execution Time: 0.128 ms
(3 rows)
```

sqlite does things a curious thing, instead of holding a tree as an internal representation it compiles down to bytecode:

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

This is what is referred to as a _query plan_, it's the _output_ of a program, like all programs, someone has to write, test and build it, this is called a query/execution engine. It takes as input a _query_ typically in a _query language_ here it's SQL and lets you retrieve 'facts':
```
postgres=# select 1 + 1;
 ?column? 
----------
        2
(1 row)
```

A query engine needs to do a few things, first it needs to be _correct_ and _fast_. Correctness is an interesting word, and it has a context that's rooted in a formalism, called [_relational algebra_](https://en.wikipedia.org/wiki/Relational_algebra), it's a little mathy but not a lot. This formalism describes a number of operations on a unordered collection of sets, with a basic set of primitives:

- select
- projection
- union
- intersection
- difference
- product(cross product)
- join
- division(*)

and a few useful modern extensions, like sorting, aggregates etc.

