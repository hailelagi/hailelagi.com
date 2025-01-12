---
title: "Query Execution"
date: 2024-10-27T14:32:18+01:00
draft: true
---

An influential modern design is the **volcano model**[^1], a popular idea for defining _execution semantics_ of a query and on the other hand the **Morsel-Driven model**[^2] some say is [the fastest table sort in the west](https://duckdb.org/2021/08/27/external-sorting.html) 

[^1]: [Volcano-An Extensible and Parallel Query Evaluation System](https://paperhub.s3.amazonaws.com/dace52a42c07f7f8348b08dc2b186061.pdf)
[^2]: [Morsel-Driven Parallelism: A NUMA-Aware Query Evaluation Framework for the Many-Core Age](https://db.in.tum.de/~leis/papers/morsels.pdf)
[^3]: [Orca: A Modular Query Optimizer Architecture for Big Data](https://www.vmware.com/docs/white-paper-orca-a-modular-query-optimizer-architecture-for-big-data)
[^4]: [Building An Elastic Query Engine on Disaggregated Storage](https://15721.courses.cs.cmu.edu/spring2023/papers/02-modern/vuppalapati-nsdi22.pdf)
