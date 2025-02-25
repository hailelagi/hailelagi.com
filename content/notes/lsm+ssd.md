---
title: "Storage + SSD = <3"
date: 2024-12-29T02:27:02+01:00
draft: true
---

## Disaggregated storage
why? elasticity(avoid over/under-provisioning), independent scalable resources, cost efficiency(economies of scale),
cloud platforms/data centers are inherently disaggregated. Primitives are pools.

Software disaggregation - aurora, socrates, neon etc how to design a DBMS to run serverless workloads?
Hardware disaggregation - pooling of resources over multi-clouds?

- compute nodes(EC2 etc)
- storage disaggregation (EBS, S3 - SSDs and NVMs) (shared vs shared-nothing)
- memory disaggregation (RDMA, persistent memory (Intel Optane(mostly dead, exists in niche production usecases)), [CXL](https://www.sigops.org/2024/revisiting-distributed-memory-in-the-cxl-era/))

challenges of memory disaggregation adoption:
>  Database systems have been heavily relying on the high speed of random
accesses to main memory to achieve good performance. Memory
disaggregation means that the majority of these accesses now become network communication. Managing remote memory accesses
is thus a key design challenge

> a large disaggregated memory pool can prevent the processing of memory-intensive queries from being spilled to secondary
storage

### For OLTP
aurora + socrates + neon

### For OLAP
snowflake, clickhouse etc

### LSM designs meet SSDs
Page server, Log server etc

### Disjoint set optimisations


[^1]: [The Log-Structured Merge-Tree](https://www.cs.umb.edu/~poneil/lsmtree.pdf)
[^2]: [Designing Access Methods: The RUM Conjecture](https://www.eecs.harvard.edu/~kester/files/rum_conjecture.pdf)
[^3]: [Understanding Modern Storage APIs](https://atlarge-research.com/pdfs/2022-systor-apis.pdf)
[^4]: [What Modern NVMe Storage Can Do, And How To Exploit It](https://vldb.org/pvldb/vol16/p2090-haas.pdf)
[^5]: [Clarifying Direct I/O Semantics](https://lwn.net/Articles/348739/)
[^6]: [What Are You Waiting For? Use Coroutines for Asynchronous I/O to Hide I/O Latencies and Maximize the Read Bandwidth!](https://db.in.tum.de/~fent/papers/coroutines.pdf)
[^7]: [The Unwritten Contract of Solid State Drives](https://pages.cs.wisc.edu/~jhe/eurosys17-he.pdf)
[^8]: [Socrates: The New SQL Server in the Cloud](https://www.microsoft.com/en-us/research/uploads/prod/2019/05/socrates.pdf)
[^9]: [Is Scalable OLTP in the Cloud a Solved Problem?](https://www.cidrdb.org/cidr2023/papers/p50-ziegler.pdf)
[^10]: [Disaggregated Database Systems](https://www.cs.purdue.edu/homes/csjgwang/pubs/SIGMOD23_Tutorial_DisaggregatedDB.pdf)
[^11]: [Immutability Changes Everything](https://www.cidrdb.org/cidr2015/Papers/CIDR15_Paper16.pdf?)
[^12]: [Dissecting, Designing, and Optimizing LSM-based Data Stores](https://cs-people.bu.edu/mathan/publications/sigmod22-sarkar-tutorial.pdf)
