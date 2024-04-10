---
title: "DIY an on-disk B+ Tree"
date: 2024-04-10T15:07:35+01:00
draft: false
tags: database internals, bookclub
---

What is a Datastructure's memory representation? Everything is either a contigous block or pointer based.
Relevant techniques: pointers, recursion and binary search - Olog(N) is powerful.

Why is it called a B-Tree? According to one of the co-inventor's [Edward M. McCreight it's short for "balance"](https://vimeo.com/73357851) -- but could mean anything :)

## Future considerations
```
- The pitfalls of memory: allocation, fragmentation & corruption
- concurrency mechanisms - MVCC
- lazy traversal: Cursor/Iter
- variants: B-link, CoW B-Trees, FD-Trees etc
- generic byte interfaces, se(de)serialisation to disk repr
- robust testing and correctness guarantees
```

## Implementation high level ideas

B-Trees are useful for:
1. In-memory indexes (also used here!)
2. persisted on disk storage organisation. <-- we're here.

Considerations:
- Performance (Access Patterns - everything is about access patterns)
- Correctness & Testing
- Durability (what's a block?, brief overview: buffered IO, mmap, directIO.)

performance big ideas overview:
- why do we want search trees? balancing and order
- going beyond Big-O - logarithmic acess.
- mutability vs immutability
- concurrency
- locality of reference(time/space) (keep stuff close togther)

## B Trees (In-Memory)
A simple and useful way of thinking of access and logarithmic bisection is a Tree of a 2-D array:

`[[1,2,3], [4,6], [9,11,12]]`

visualisation: 
https://www.cs.usfca.edu/~galles/visualization/BPlusTree.html

desired properties:
- high fanout (dense trees)
- short height

```go
/*
Simple Persistent B Plus Tree.
Node keys are assumed to be signed integers and values in a
slice of bytes. Persistence is achieved using a naive bufio.Writer 
interface pointer for simplicity.Concurrency control is achieved 
using a simple globally blocking RWMutex lock.

B-Tree implementations have many implementation specific details 
and optimisations before they're 'production' ready, notably they 
may use a free-list to hold cells in the node and employ 
sophisticated concurrency control.
// see also: CoW semantics

// learn more:
// etcd: https://pkg.go.dev/github.com/google/btree
// sqlite: https://sqlite.org/src/file/src/btree.c
// wiki: https://en.wikipedia.org/wiki/B%2B_tree
*/
```

Definition:

A B plus tree with an arbitrary max degree 3, degree is the number of pointers/children each node can point to/hold:

```go
const (
	MAX_DEGREE = 3
)

const (
	ROOT_NODE NodeType = iota + 1
	INTERNAL_NODE
	LEAF_NODE
)

type BTree struct {
	root *Node
}
```

A node:

```go
type Node struct {
	kind     NodeType
	// maintaining a parent pointer is expensive
	// in internal nodes especially
	parent   *Node
	keys     []int
	children []*Node
	data     []int

	// sibling pointers these help with deletions + range queries
	next     *Node
	previous *Node
}

```

**Operations Overview**:
- insertion/split algorithm
```go
func (n *node) split(midIdx int) error {
// every node except the root node must respect the inquality:
// branching factor - 1 <= num keys < (2 * branching factor) - 1

// if this doesn't make sense ignore it. The take away:
// every node except root has a minimum no. of keys or it's invalid.

// edge case, how to handle the root node?

// step two: it's promotion time, split keys into two halves
	splitPoint := n.keys[midIdx]
	leftKeys := n.keys[:midIdx]
	rightKeys := n.keys[midIdx:]

	n.keys = []int{splitPoint}

	leftNode := &node{kind: LEAF_NODE, keys: leftKeys}
	rightNode := &node{kind: LEAF_NODE, keys: rightKeys}
	n.children = []*node{leftNode, rightNode}


// -- LEAF
//  (internal node)  (internal or nil)
//   \               /
//   (root)

// step three, check all children:
// recurse UP from root to new internal node(s),
// check that we're not full if full, we split 
// again on internal node, allocate a new node(s)
// --snipped for clarity
	return nil
}
```
- access

```go
func (n *Node) basicSearch(key int) *Node {
	if len(n.children) == 0 {
// you are at a leaf Node and can now access stuff
// or this is the leaf node that should contain stuff
		return n
	}

	low, high := 0, len(n.keys)-1
	for low <= high {
		mid := low + (high-low)/2
		if n.keys[mid] == key {
			return n
		} else if n.keys[mid] < key {
			low = mid + 1
		} else {
			high = mid - 1
		}
	}

	return n.children[low]
}
```
- deletion
```go
// TODO: 
func (n *Node) mergeSibling(sibling *Node, key int) error {
	if n.parent != sibling.parent {
		panic("sibling invariant not satisfied")
	}

	switch n.kind {
	case LEAF_NODE:
		sibling.keys = append(sibling.keys, n.keys...)

		for i, node := range sibling.parent.children {
			if node == n {
				n.parent.children = append(n.parent.children[:i], n.parent.children[i+1:]...)
			}
		}

		for i, k := range n.parent.keys {
			if k == key {
				n.parent.keys = cut(i, n.parent.keys)
				newSplit := len(n.data) / 2

				if len(n.data) != 0 {
					n.parent.keys = append(n.parent.keys, n.data[newSplit])
				}

				if len(n.parent.keys) < ((MAX_DEGREE - 1) / 2) {
					if sibling, err := n.parent.preMerge(); err == nil {
						return n.parent.mergeSibling(sibling, key)
					} else {
						return errors.New("see rebalancing.go")
					}
				}
			}
		}

	case INTERNAL_NODE:
		if len(n.parent.keys) < ((MAX_DEGREE - 1) / 2) {
			if sibling, err := n.parent.preMerge(); err == nil {
				return n.parent.mergeSibling(sibling, key)
			} else {
				return errors.New("see rebalancing.go")
			}
		}
	}

	return nil
}

```

## B Trees (Going to Disk)
# TBD

## Tools of the Trade
Base your judgement on empirical fact:

- a good debugger or not (dbg etc)
- [flamegraphs](https://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html)
- benchmarking
- tests - unit, integration, fuzzing, proptests, simulations etc


Performance comes from thinking wholistically about hardware and software together.
Optimizations bear the fruits of pretty benchmarks and complexity.
The first big piece is concurrency and parallelism.

tldr; the hard part about building storage engines is debugging and testing them, old databases are good because time spent in production uncovering (or not uncovering bugs).

In the real world stuff goes wrong(the operating system hides hardware and software faults, but you have to care), data loss is bad and is a big no-no.

### Running in production: Correctness, Testing & Safety
Complexity is **evil** but unavoidable, non-determinism makes you helpless.

testing methodology, loom - concurrency is hard etc:
- How SQLlite is tested: https://www.sqlite.org/testing.html
- Valgrind, Address and Memory Sanitizer
- https://www.cs.utexas.edu/~bornholt/papers/shardstore-sosp21.pdf
- https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/DESIGN.md#safety
- https://apple.github.io/foundationdb/testing.html
- many more...

## Further reading: storage engine architecture
Move towards modularization of database components, decoupled query & execution engine(velox, datafusion etc), storage engine see: [foundationDB](https://apple.github.io/foundationdb/layer-concept.html).

What the heck is going on in your favorite database? _select/biased_ popular deep dives into 
popular storage engines for: postgres/postgres, kubernetes/etcd, mysql/InnoDB, mongodb(WiredTiger):

postgres:
https://postgrespro.com/blog/pgsql/4161516

etcd: https://etcd.io/docs/v3.5/learning/data_model/

innodb: https://dev.mysql.com/doc/refman/8.0/en/innodb-physical-structure.html

mongodb: https://source.wiredtiger.com/11.2.0/arch-btree.html

Things we've come to want/expect out of modern databases:
- Seperation of Storage and Compute: https://clickhouse.com/docs/en/guides/separation-storage-compute
- Multitenancy: https://github.com/neondatabase/neon/blob/main/docs/multitenancy.md
- Distribution/Replication: Availability, Redundancy & Serverless style scale
- DBaaS/Cloud Native Stateful Backend services + Database engine, supabase etc
