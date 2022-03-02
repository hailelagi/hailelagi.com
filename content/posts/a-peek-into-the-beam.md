---
title: "A Peek Into the Beam"
date: 2022-03-02T08:16:09+01:00
draft: true
---

A long time ago, you would give a computer an intensive set of instructions - in assembly or something more sane, and 
it would compute these instructions one by one, but while it did that - it would “freeze up” you couldn’t really do much
else with it. At the time, computer hardware was pretty limited, it had single CPU core 
(something that executes instruction sets) which did pretty much everything - computer scientists were not particularly 
satisfied with this and they [found a solution](https://en.wikipedia.org/wiki/Mutual_exclusion). 

In essence, execution of two or more computations is possible at the same time - given it is guaranteed that both read
data from the same source at the same time, but writing could lead to inconsistency - commonly known as a data race. 
Today our computers have multiple cores - they can do a lot more stuff than they used to.

The world of concurrency is fascinating, lots of languages design mechanisms around this problem known as 
concurrency primitives, allowing software creators to fashion applications and software systems that perform much better
than their sequential alternative, however we are most interested in a cursory glance into the BEAM 
(Erlang’s virtual machine). For brief context a virtual machine is just software - an abstraction over the basic
hardware of a computer allowing a layer of execution on top of it.

source code(elixir or erlang) --> bytecode(opcodes for the vm) --> c interface  -->  assembly/machine code

Most of the interesting [concurrency primitives](https://en.wikipedia.org/wiki/Actor_model) that erlang/elixir provide 
are built on top of the [guarantees](https://ferd.ca/it-s-about-the-guarantees.html) this virtual machine provides such as immutable state. The single basic unit being 
a process - an isolated sequential unit of computation which is managed by a scheduler.

### Erlang’s scheduler

The scheduler within the BEAM runtime (not an operating system scheduler lol), talks to the operating system and 
manages the [how and when](https://hamidreza-s.github.io/erlang/scheduling/real-time/preemptive/migration/2016/02/09/erlang-scheduler-details.html)
of computations (processes). It does something called preemptive scheduling. There’s a nuanced trade off being considered here -
All processes are treated as equal and given a tiny block of time/memory to execute, whether or not this is enough 
for a process is irrelevant. It sacrifices the efficient allocation of resources to process that need it most to make 
some important guarantees which make fault tolerance possible:

1. High availability
2. Isolated failure states

These guarantees gives us a system that is highly introspectable :observer module - attach a screenshot) where we can
leverage this information to make intelligent deductions about what is happening within the system and even design
mechanisms to deal with and understand crashes and fail states, while also providing concurrent primitives that naturally
scale across distributed systems, changing very little about the core system:
Vertically - more cores, power to you. The BEAM uses all it can get.
Horizontally - distributed servers are just process nodes that send each other messages.
