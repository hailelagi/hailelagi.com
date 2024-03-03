---
title: "Database Internals: B Tree Basics - TalkPoints"
date: 2024-02-29T12:49:19+01:00
draft: false
---

Simple walkthrough/guide

Recap storage engines at the heart B-Tree.
Data structures contiguous vs pointer based.
* Honorable mention hashmap
Binary Search Trees - Dictionary Data type/Map
balancing

disk considerations
data set cannot fit in memory, we must cache and page in and out of memory.
> “we have to perform balancing, relocate nodes, and update pointers rather frequently. Increased maintenance costs make BSTs impractical as on-disk data structuree”

HDDs vs SSDs
how they work
important - block device abstraction
locality of reference

goals:
- minimize expensive disk seeks
- min random IO, max sequential IO
- minimize pointer management

B Trees:
we actually mean Bplus Tree.
sorted data structure, pointer based = binary search.

B-Trees are useful for:
1. In-memory indexes (also used here!)
2. persisted on disk storage organisation. <-- we're here.

“Since B-Trees are a page organization technique (i.e., they are used to organize and navigate fixed-size pages), we often use terms node and page interchangeably.”


desired properties:
- high fanout
- low height

terms:
degree/occupancy/branching factor
root
internal node - separator key
leaf node

operations
- insert
- search (point and range) + block transfers
- deletion


internal operations:
- splits on insertion 
- merges on deletion


final - implementation is on chapter four, we shall revisit again!
