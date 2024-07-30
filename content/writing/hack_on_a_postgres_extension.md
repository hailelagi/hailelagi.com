---
title: "Hacking on a postgres extension - feelings"
date: 2024-03-17T01:25:30+01:00
draft: true
---

this will probably be my next project, doing something with postgres.

https://github.com/pgcentralfoundation/pgrx

### Pros
- it's actual database development: on a platform rather DIY from scratch(impossible goal), knowledge of internals is helpful.
- I like postgres/sort of already know it a little from a user perspective.
- breaking databases is fun, it feels good to add and remove things, hack around.

### Cons

- context switches are extremely expensive - more so than typical projects: there is alot to keep in your head, meaning at most you
can only ever work on a handful of specific projects, ideally just one at a time. I don't do this because I'm unsure if this what I 
want to be doing.
- the compile times are really bad (this is not fun)
- because C and therefore means learning/reading writing unsafe rust
(this is not fun)
