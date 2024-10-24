---
title: "How do databases count?"
date: 2024-10-16T19:05:55+01:00
draft: true
tags: go, rust, sql, probability
---

Given the simple query below, how does a database count?
```
psql -U postgres
select count(distinct col1) from table1;
```

Let's ask the database directly, [in this case, it's postgres](https://www.postgresql.org/docs/current/using-explain.html):

```
explain analyze select count(distinct col1) from table1;
```

This produces a long series of arcane sounding words and structures, an output as a _tree_ of algorithmic paths/steps, which you can _read bottom-up_, a trivial example which is [_inlined_](https://wiki.postgresql.org/wiki/Inlining_of_SQL_functions) and doesn't need a series of 'optimisation passes':
```
postgres=# explain analyze select 1 + 1;
                                     QUERY PLAN                                     
------------------------------------------------------------------------------------
 Result  (cost=0.00..0.01 rows=1 width=4) (actual time=0.001..0.012 rows=1 loops=1)
 Planning Time: 0.522 ms
 Execution Time: 0.128 ms
(3 rows)
```

This is not the only way to represent a query plan, sqlite on the other hand does a curious thing, instead of holding a tree as an internal representation, it compiles [down to bytecode](https://www.sqlite.org/opcode.html), why it makes this decision is a plenty interesting design space[^2]:

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

This is what is referred to as a _query plan_, it's the _output_ of a program, like all programs, it has a rich history, architectural decisions, algorithms, datastructures, trade-offs and constraints. It takes as input a _query_ typically in a _query language_ here it's SQL and lets you retrieve 'facts' by isolating the how from the underlying storage, this **decoupling** gives many benefits and in [hindsight is obvious](https://en.wikipedia.org/wiki/Data_independence), but wasn't always so, until someone(s) figured it out[^1]:
```
postgres=# select 1 + 1;
 ?column? 
----------
        2
(1 row)
```

Let's make a small query engine, to answer our question:

```
select count(distinct col) from table;
```

The goals of a query engine specify the _need_ to be **_correct_** and **_fast_** as data grows. Correctness is an interesting word, and it has a context that's rooted in a two part formalism, called [_relational algebra_](https://en.wikipedia.org/wiki/Relational_algebra) and **relational calculus.** 

Of interest is how the first formalism describes a number of operations on a _unordered collection_ of sets:

- select
- projection
- union
- intersection
- difference
- product(cross product)
- join
- division(*)

and a few useful modern extensions, like sorting, windows, aggregates etc.

To answer this query, it seems we need to _plan_ several things, two _logical operators_ or _logical nodes_ which define this transformation:
1. select - to specify we want a final count
2. projection - to specify _which_ column is of interest

and a [function](https://www.postgresql.org/docs/9.2/functions.html), in this case an **aggregate function** called `COUNT(expr)`, and finally some 
way to represent relations in this naive engine:

```go
/*
schema col -> row mapping
[{k,v}, {k,v}, {k,v}, {k,v}]
*/
type Relation struct {
	colNames []string
	rows     []Row
}
```

A selection is:
```go
// selection table/relation + predicate (expr = true | false | unknown)
// σ predicate(R).
// 1. constant
// 2. equality selection
// SQL: SELECT * FROM R WHERE a_id = 'a2'

func ConstantSelect(relation Relation, idx int, expr string) Relation {
	result := make([]Row, 0)

	for _, r := range relation.rows {
		if r[idx] == expr {
			result = append(result, r)
		}
	}

	return Relation{
		colNames: relation.colNames,
		rows:     result,
	}
}
```

A projection is:
```go
// Projection: modification(r/w/order) over columns, changes the shape of output/attributes
// π(a1,a2),. . . , (a)n(R).
// SQL: SELECT b_id-100, a_id FROM R WHERE a_id = 'a2'
func Projection(relation Relation, columns []int) Relation {
	result := make([]Row, 0)

	for _, row := range relation.rows {
		newRow := make(Row, len(columns))

		for i, colIdx := range columns {
			newRow[i] = row[colIdx]
		}

		result = append(result, newRow)
	}

	colNames := make([]string, len(columns))

	for i, colIdx := range columns {
		colNames[i] = relation.colNames[colIdx]
	}

	return Relation{
		colNames: colNames,
		rows:     result,
	}
}
```

Now we have a **logical plan** of operations and transformations on this query, but it's defined in a _syntax_ for these operations, re-enter SQL, or was it SEQUEL? Of note is the observation, the **logical operations are independent of the syntax** used to describe them. We need to first parse the sql, and build a simple abstract syntax tree where the nodes are the logical operators: selection, projection and preserving the semantics of applying the `count`, parsing such a simple query doesn't require a [sophisticated scheme that's generalized over a grammar](https://en.wikipedia.org/wiki/Recursive_descent_parser) all we need is:
```go
// parser.go

```

### Query Processing and Cost Optimisation

Lastly, all that's left is to `count`. Which brings us to feature two -- **performance**. A historical glance reveals some influential architectural decisions, we've established the need to seperate the _logical_ what of a query from the _physical_ how the query finds and further yet, realised sql (and dialects) are really syntactic abstractions.

Why is the performance of counting interesting? What are the **problems**, programs are written for computers, how do you leverage all the ways a computer allows you to be fast? how do you take a program, any program, and run it across **multiple cores** and leverage hardware advances that run in data centers **distributed** across computers? https://en.wikipedia.org/wiki/Count-distinct_problem

> The situation gets much more complex when operations like projections, selections, multiple joins
 in combination with various boolean operations appear in queries. As an example, the relational s
 ystem system R has a sophisticated query optimiser. In order to perform its task, that programme keeps several statistics on
relations of the data base. The most important ones are the sizes of relations as well
as **the number of different elements of some key fields** [8]. This information is used
to determine the selectivity of attributes at any given time in order to decide the
choice of keys and the choice of the appropriate algorithms to be employed when
computing relational operators. The choices are made in order **to minimise a certain cost function** that depends on specific CPU and disk access costs as well as sizes and cardinalities of relations or fields. In system R, this information is
periodically recomputed and kept in catalogues that are companions to the database records and indexes[^3]

An influential modern design is the **volcano model**[^4], a popular idea for defining _execution semantics_ of a query and on the other hand the **Morsel-Driven model**[^5] some say is [the fastest table sort in the west](https://duckdb.org/2021/08/27/external-sorting.html) 

todo: approach? minimal execution layer?
```
```

### Naive/Strawman Counting
- stack
```go
```

- hashmap

```go
```

### Probabilistic Counting

The intuition:

{{% callout %}}
observing in the stream S at the beginning of a string a bit- pattern 0ρ−11 is more or less a likely indication that the cardinality n of S is at least 2ρ
{{% /callout %}}

```

```

Hashing functions + basic probability, explain the intuition

### Morris Counter
Morris Counter[^4]: `log2 log2 /1 + O( 1)`

```go
```

### Probabilistic Cardinality Estimation with HyperLogLog

Time Complexity: **O(1)**

Space Complexity: **O(log log N)**

Parallel: (✅)

This algorithm allows the estimation of cardinality of datasets to the tune of over a billion! using only ~1.5kilobytes, and a margin of error of roughly 98% accuracy, those are incredible numbers


definitions:
1. multiset = stream, elements to be counted belonging to a certain data domain D via a hash function:
2. hash_fn : Domain → {0, 1}∞

rely on making observations on the hashed values h(M) of the input multiset M
then inferring a plausible estimate of the unknown cardinality n. These observations are:
- Bit-pattern observables
- Order statistics observables

observable of a multiset(S) `S ≡ hash_fn(Multiset) of {0, 1}∞`

Why?

m = 2 ^ p

Pseudo code:
Let h : D → [0, 1] ≡ {0, 1}∞ hash data from domain D to the binary domain. Let ρ(s), for s ∈ {0, 1}∞ , be the position of the leftmost 1-bit (ρ(0001 · · · ) = 4).
Algorithm HYPERLOGLOG (input M : multiset of items from domain D). assumem=2b withb∈Z>0;
initialize a collection of m registers, M [1], . . . , M [m], to −∞;
for v ∈ M do
set x := h(v);
set j = 1 + ⟨x1x2 · · · xb⟩2; {the binary address determined by the first b bits of x} set w := xb+1xb+2 · · · ; set M[j] := max(M[j], ρ(w));
!−1
m computeZ:= X2−M[j]
j=1
;{the“indicator”function} return E := αmm2Z with αm as given by Equation (3).
```

include pseudo code from the paper? A quick definition of terms:
```
Let h : D → {0, 1}32 hash data from D to binary 32–bit words.
Let ρ(s) be the position of the leftmost 1-bit of s: e.g., ρ(1···) = 1, ρ(0001···) = 4, ρ(0K) = K + 1.
define α16 = 0.673; α32 = 0.697; α64 = 0.709; αm = 0.7213/(1 + 1.079/m) for m ≥ 128;
```

psuedo code:
```
Program HYPERLOGLOG (input M : multiset of items from domain D). 
assume m = 2b with b ∈ [4..16].
initialize a collection of m registers, M [1], . . . , M [m], to 0;
for v ∈ M do
  set x := h(v);
  set j = 1 + ⟨x1x2 · · · xb⟩2; {the binary address determined by the first b bits of x}
  set w := xb+1xb+2 ···;
  set M[j] := max(M[j], ρ(w)); „m «−1

compute E := αm m2 · X 2−M [j ] ; {the “raw” HyperLogLog estimate} j=1

if E ≤ 25 m then
   let V be the number of registers equal to 0;
   if V ̸= 0 then set E⋆ := m log(m/V ) else set E⋆ := E; {small range correction}

if E ≤ 1/2^32 then 30
set E⋆ := E;  {intermediate range—no correction}
if E > (1/30)(2^32) then
set E⋆ := −232 log(1 − E/232); {large range correction} 
return cardinality estimate E⋆ with typical relative error ±1.04/ m.
```



todo: port over the c++ to rust

```rust
```

HyperLogLog is now a fairly standard data structure in analytics databases, despite being invented relatively not that long ago, a few examples of adoption in the postgres ecosystem are: [citus](https://docs.citusdata.com/en/stable/articles/hll_count_distinct.html), [crunchydata](https://www.crunchydata.com/blog/high-compression-metrics-storage-with-postgres-hyperloglog) and [timescaleDB](https://docs.timescale.com/use-timescale/latest/hyperfunctions/approx-count-distincts/hyperloglog/), broadly at [meta(presto)](https://engineering.fb.com/2018/12/13/data-infrastructure/hyperloglog/), in [google](http://research.google/pubs/hyperloglog-in-practice-algorithmic-engineering-of-a-state-of-the-art-cardinality-estimation-algorithm/) at [Big Query](https://cloud.google.com/bigquery/docs/reference/standard-sql/hll_functions) and much more. Thanks for reading!


[^1]: [System R](https://www.seas.upenn.edu/~zives/cis650/papers/System-R.PDF)
[^2]: [Everything You Always Wanted to Know About Compiled and Vectorized Queries But Were Afraid to Ask](https://www.vldb.org/pvldb/vol11/p2209-kersten.pdf)
[^3]: [Probabilistic Counting Algorithms for Database Applications](https://algo.inria.fr/flajolet/Publications/src/FlMa85.pdf)
[^4]: [Counting Large Numbers of Events in Small Registers ](https://www.inf.ed.ac.uk/teaching/courses/exc/reading/morris.pdf)
[^4]: [Loglog Counting of Large Cardinalities](https://algo.inria.fr/flajolet/Publications/DuFl03-LNCS.pdf)
[^5]: [HyperLogLog: the analysis of a near-optimal cardinality estimation algorithm](https://algo.inria.fr/flajolet/Publications/FlFuGaMe07.pdf)
[^6]: [Volcano-An Extensible and Parallel Query Evaluation System](https://paperhub.s3.amazonaws.com/dace52a42c07f7f8348b08dc2b186061.pdf)
[^7]: [Morsel-Driven Parallelism: A NUMA-Aware Query Evaluation Framework for the Many-Core Age](https://db.in.tum.de/~leis/papers/morsels.pdf)
