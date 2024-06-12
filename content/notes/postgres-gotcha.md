---
title: "Postgres Gotcha"
date: 2024-05-31T19:03:24+01:00
draft: false
---

general: https://rbranson.medium.com/10-things-i-hate-about-postgresql-20dbab8c2791

1. Transaction ID wrap around:
- https://blog.sentry.io/transaction-id-wraparound-in-postgres/
- https://www.notion.so/blog/sharding-postgres-at-notion

2. Concurrent Indexes
- https://www.braintreepayments.com/blog/safe-operations-for-high-volume-postgresql/
- https://fly.io/phoenix-files/safe-ecto-migrations/
-

3. Replication is async and data loss is possible on fail over:
- https://wiki.postgresql.org/wiki/Streaming_Replication
- https://www.postgresql.org/docs/current/logical-replication-restrictions.html
- https://www.postgresql.org/docs/16/warm-standby.html
- https://neon.tech/docs/introduction/read-replicas

4. Write amplification on TOAST, large indexes, large columns bad.
https://ottertune.com/blog/the-part-of-postgresql-we-hate-the-most

