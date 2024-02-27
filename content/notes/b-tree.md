---
title: "Database Internals: B Tree Basics"
date: 2024-02-27T12:44:49+01:00
draft: true
---

why is it called a B-Tree? According to one of the co-inventor's [Edward M. McCreight it's short for "balance"](https://vimeo.com/73357851).

## Testing
testing methodology, loom - concurrency is hard etc:
- https://www.cs.utexas.edu/~bornholt/papers/shardstore-sosp21.pdf



### Further Reading
What the heck is going on in your favorite database? Here's a few select
popular deep dives into postgres/postgres, kubernetes/etcd, mysql/InnoDB, mongodb(WiredTiger):

postgres:
https://postgrespro.com/blog/pgsql/4161516

etcd: https://etcd.io/docs/v3.5/learning/data_model/

innodb: https://dev.mysql.com/doc/refman/8.0/en/innodb-physical-structure.html

mongodb: https://source.wiredtiger.com/11.2.0/arch-btree.html
