---
title: "How do databases count?"
date: 2024-11-05T18:13:34+01:00
draft: false
tags: rust, go, sql, probability
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

This produces a series of algorithmic steps and structures specific to a database, outputted as a _tree_ of "paths", which you can _read bottom-up_, a trivial example which is [_inlined_](https://wiki.postgresql.org/wiki/Inlining_of_SQL_functions) and doesn't need a series of 'optimisation passes':
```
postgres=# explain analyze select 1 + 1;
                                     QUERY PLAN                                     
------------------------------------------------------------------------------------
 Result  (cost=0.00..0.01 rows=1 width=4) (actual time=0.001..0.012 rows=1 loops=1)
 Planning Time: 0.522 ms
 Execution Time: 0.128 ms
(3 rows)
```

This is not the only representation of a query plan, sqlite on the other hand does a curious thing, instead of holding a tree as an internal representation, it compiles [down to bytecode](https://www.sqlite.org/opcode.html), why it makes this decision is a plenty interesting design space[^3]:

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

If you'd rather see the plan, rather than reading opcodes:
```
sqlite> explain query plan select 1 + 1;
QUERY PLAN
`--SCAN CONSTANT ROW
```

A query plan is the _output_ of a program, like all programs, it has a rich history, architectural decisions, algorithms, datastructures, trade-offs and constraints. It takes as input a _query_ typically in a _query language_ here it's SQL and lets you retrieve 'facts' by isolating the how from the underlying storage, this **decoupling** gives many benefits and in [hindsight is obvious](https://en.wikipedia.org/wiki/Data_independence), but wasn't always so, until someone(s) figured it out[^1] [^2]:
```
postgres=# select 1 + 1;
 ?column? 
----------
        2
(1 row)
```

To answer our question, a tiny, not at all functional, but illustrative, query engine in [less than 500 lines](https://github.com/hailelagi/peppermint) of rust:

```
select count(distinct col) from table;
```

The goals of a query engine specify the _need_ to be **_correct_** and **_fast_** as data grows. Correctness is an interesting word, and it has a context that's rooted in a two part formalism, called [_relational algebra_](https://en.wikipedia.org/wiki/Relational_algebra) and **relational calculus.** 

Of interest is how the first formalism describes a number of operations on a _unordered collection_ of sets:

- selection
- projection
- union
- intersection
- difference
- product(cross product)
- join
- division(*)

and a few useful modern extensions, like sorting, windows, aggregates etc.

To answer this query, it seems we need to _plan_ several things, two _logical operators_ or _logical nodes_ which define this transformation:
1. select - to specify what we want
2. projection - to specify a few details about what is of interest

and a [function](https://www.postgresql.org/docs/9.2/functions.html), in this case an **aggregate function** called `COUNT(expr)`, and finally some 
way to represent relations in this naive engine, we don't have  a real 'schema' quite yet or ever will, but you could imagine a relation as:

```rust
/*
schema: relation + col -> row mapping
storage(tuples): [{k,v}, {k,v}, {k,v}, {k,v}]
*/
#[derive(Debug, Clone)]
pub struct Relation {
    pub col_names: Vec<String>,
    pub rows: Vec<Vec<String>>,
}
```

A selection here does a full scan and filters out based on the predicate:
```rust
// selection table/relation + predicate (expr = true | false | unknown)
// σ predicate(R). SQL: SELECT * FROM R WHERE a_id = 'a2'
    pub fn select(&self, idx: usize, expr: &str) -> Relation {
        let result: Vec<Vec<String>> = self.rows
            .iter()
            .filter(|row| row[idx] == expr) 
            .cloned()
            .collect();

        Relation {
            col_names: self.col_names.clone(), 
            rows: result,
        }
    }

```

A projection here is a _modifier_ operation over the set:
```rust
// Projection: modification(r/w/order) over cols, changes the shape of output/attributes
// π(a1,a2),. . . , (a)n(R).
// SQL: SELECT b_id-100, a_id FROM R WHERE a_id = 'a2'
    pub fn projection(&self, columns: &[usize]) -> Relation {
        let result: Vec<Vec<String>> = self.rows
            .iter()
            .map(|row| {
                columns.iter()
                .map(|&col_idx| row[col_idx].clone()).collect()
            }).collect();

        let col_names: Vec<String> = columns
            .iter()
            .map(|&col_idx| self.col_names[col_idx].clone())
            .collect();

        Relation {
            col_names,
            rows: result,
        }
    }
```

Now we have a **logical plan** of operations and transformations on this query, but it's defined in a _syntax_ for these operations, 
re-enter SQL, or was it SEQUEL? Of note is the observation, the **logical operations are independent of the syntax** used to describe them.
We need to first parse the sql, and build a simplified abstract syntax tree where the nodes are the logical operators: selection, projection
and preserving the semantics of applying the `count`, luckily this query engine doesn't need to support the SQL standard or dialects! 
and we can cut corners :) , we can just parse out exactly what's needed, without [walking the tree](https://docs.rs/sqlparser/latest/sqlparser/ast/trait.Visitor.html) or [using a pretty cool generalization over a grammar](https://en.wikipedia.org/wiki/Recursive_descent_parser):
```rust
// parser.rs parse SELECT COUNT(DISTINCT col) FROM table; 
// and produces a data structure post logical we'd now pass to the
// 'physical/execution' planning stage, select indices etc
// in this example, there's only one possible strategy `SeqScan`
// in a strict sense is a combined logical + physical?
SelectStatement {
            projection: AggregateExpression {
                function: Aggregation::Count,
                column: Column {
                    name: "col".to_string(),
                    distinct: true,
                },
            },
            table: "table".to_string(),
        };

```

### Statistics & Costs

Lastly, all that's left is to `count`. Which brings us to feature two -- **performance**. A historical glance reveals some influential architectural decisions, we've established the need to seperate the _logical_ what of a query from the _physical/execution_ how the query finds,
in this simplified all-in-one planner, we gloss over that very important detail and further yet, realised sql (and dialects) are really syntactic abstractions.

Why is the performance of counting interesting? 

> The situation gets much more complex when operations like projections, selections, multiple joins
 in combination with various boolean operations appear in queries. As an example, the relational system system R has a sophisticated query optimiser. In order to perform its task, that programme keeps **several statistics** on
relations of the database. The most important ones are the **sizes of relations** as well
as **the number of different elements of some key fields** [8]. This information is used
to determine the selectivity of attributes at any given time in order to decide the
choice of keys and the choice of the appropriate algorithms to be employed when
computing relational operators. The choices are made in order **to minimise a certain cost function** that depends on specific CPU and disk access costs as well as **sizes and cardinalities** of relations or fields. In system R, this information is
periodically recomputed and kept in catalogues that are companions to the database records and indexes[^3]

In postgres this subsystem is called the [Cumulative Statistics System](https://www.postgresql.org/docs/current/monitoring-stats.html), hopefully this contextualizes _why_ keeping track of counts and making them fast is important. It's not just to serve the sql query aggregate function `COUNT`, it's also quite useful internally for the planner as well.

### Naive Counting
There are two flavors of counting, we're interested in:
1. size (counting all elements)
2. cardinality (roughly, counting unique elements)

Counting elements for an exact size, could be as simple as a counter, an [`ADD` instruction is very fast](https://c9x.me/x86/html/file_module_x86_id_5.html), but if we're storing _alot of different counts_, wouldn't it be nice if we could save on memory too? what if you don't care about an _exact_ count? say we only desire a _rough count_ over some interval to make some informed decisions?

On the other side of the coin, how do we count _unique elements_?

```go
// This is computationally inefficient in time
func countUniqStack(arr []int) int {
	mystack := MyStack{}

	for _, element := range arr {
                // expensive check
		if !mystack.contains(element) {
			mystack.stack = append(mystack.stack, element)
		}
	}

	return len(mystack.stack)
}
```

Perhaps a hashmap which is `O(1)`?
```go
// This is computationally inefficient in space
// For a large set s, we must `make` unused space 'incase'
func countUniqMap(arr []int) int {
	seen := make(map[int]bool)
	uniqs := []int{} 

	for _, element := range arr {
		if !seen[element] {
			uniqs = append(uniqs, element) 
			seen[element] = true
		}
	}

	return len(stack) 
}
```

It seems like a stack and hashmap won't work, how does one store less and compute only what's necessary?

### Probabilistic counting

Two interesting and clever data structures, relax the requirement of counting _exact_ elements in a stream by using probabilistic schemes that offer a _sketch_, the Morris Counter[^4] and the HyperLogLog. The morris counter saves on the _space_ that's required to represent or hold the reprentation of a _stream_, it gets a little "mathy" [if you're interested this excellent blog post has a great explaination to intuit the math](https://gregorygundersen.com/blog/2019/11/11/morris-algorithm/).

The hyperloglog on the other hand allows for the estimation of cardinality of datasets to the tune of over a billion! using only ~1.5kilobytes, and a margin of error of roughly 98% accuracy, those are incredible numbers, [^5] how does it work? 

The input to this algorithm is a _continuous stream_ (elements are read sequentially) say:

 `["hello", "bye, "hello", "world", "universe", "foo"]` 

We want to perform a _single pass_ over these elements(_multiset_ in the paper) and the output an _estimate of the cardinality_ 
of unique items when we're done by utilising a hash function to produce a uniformly random binary over each element:

`hash_fn : Domain → {0, 1}∞`

Which might produces a binary stream(S) like:

```
[101010, 100000, 00100, 0000101, 0100101]
```

The paper draws attention on making some observations about _patterns_ in the bits produce which allow us to infer a plausible estimate of the unknown cardinality n. These observations are:

- Bit-pattern observables
- Order statistics observables

In particular we're focused on the first _bit-pattern_ observables:

{{% callout %}}
in the stream S at the beginning of a string a bit-pattern 0^(ρ−1) . 1 is more or less a likely indication that the cardinality n of S is at least 2ρ
{{% /callout %}}

Once we've identified this pattern in the hashed bit, we can then _combine_, several "estimation passess" by making each "guess" in parallel and later combining them using a pretty neat formula, it's a short algorithm but requires some clever bit shifting and finding a uniform hash that behaves properly.

HyperLogLog is now a fairly standard data structure in analytics databases and realtime/main memory databases, a few examples of adoption in the postgres ecosystem are: [citus](https://docs.citusdata.com/en/stable/articles/hll_count_distinct.html), [crunchydata](https://www.crunchydata.com/blog/high-compression-metrics-storage-with-postgres-hyperloglog) and [timescaleDB](https://docs.timescale.com/use-timescale/latest/hyperfunctions/approx-count-distincts/hyperloglog/), broadly at [meta(presto)](https://engineering.fb.com/2018/12/13/data-infrastructure/hyperloglog/), in [google](http://research.google/pubs/hyperloglog-in-practice-algorithmic-engineering-of-a-state-of-the-art-cardinality-estimation-algorithm/) at [Big Query](https://cloud.google.com/bigquery/docs/reference/standard-sql/hll_functions), [Redis](https://antirez.com/news/75) and much more. 

{{% callout color="#ffd700" %}}
If you enjoyed reading this please consider thoughtfully sharing it with someone who might find it interesting!
{{% /callout %}}

[^1]: [Access Path Selection in a Relational Database Management System](https://courses.cs.duke.edu/compsci516/cps216/spring03/papers/selinger-etal-1979.pdf)
[^2]: [System R](https://www.seas.upenn.edu/~zives/cis650/papers/System-R.PDF)
[^3]: [Everything You Always Wanted to Know About Compiled and Vectorized Queries But Were Afraid to Ask](https://www.vldb.org/pvldb/vol11/p2209-kersten.pdf)
[^4]: [Probabilistic Counting Algorithms for Database Applications](https://algo.inria.fr/flajolet/Publications/src/FlMa85.pdf)
[^5]: [Counting Large Numbers of Events in Small Registers ](https://www.inf.ed.ac.uk/teaching/courses/exc/reading/morris.pdf)
[^6]: [Loglog Counting of Large Cardinalities](https://algo.inria.fr/flajolet/Publications/DuFl03-LNCS.pdf)
[^7]: [HyperLogLog: the analysis of a near-optimal cardinality estimation algorithm](https://algo.inria.fr/flajolet/Publications/FlFuGaMe07.pdf)


#### Notes & References
- https://15445.courses.cs.cmu.edu/spring2023/notes/01-introduction.pdf
- https://15445.courses.cs.cmu.edu/fall2024/notes/02-modernsql.pdf
- https://www.algorithm-archive.org/contents/approximate_counting/approximate_counting.html
