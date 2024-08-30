---
title: "PAM - The match specification"
date: 2024-02-09T12:52:27+01:00
draft: true
tags: ['archive']
publicDraft: true
---

⚠️⚠️⚠️⚠️
This a WIP draft
⚠️⚠️⚠️⚠️

This is a two part series on building an in-memory [key value store](https://en.wikipedia.org/wiki/In-memory_database):

1. [The storage engine](../tsunami_one)
2. [The query engine/parser](./)

## Part Two - The query parser and engine

https://www.erlang.org/doc/apps/erts/match_spec#:~:text=A%20%22match%20specification%22%20(match_spec,example%20ets%3Aselect%2F2.

Every good database needs ergonimics features fo good querying! SQL is amazing but is insanely complex to implement and tightly coupled to transaction semantics,
however we don't want to feel left out, let's build a tiny(compared to sql) query syntax and engine.
v