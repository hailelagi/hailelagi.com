---
title: "A Peek Into the Beam"
date: 2022-03-02T08:16:09+01:00
draft: false
---

A long time ago, you would give a computer an intensive set of instructions - in assembly or something more sane, and 
it would compute these instructions one by one, but while it did that - it would “freeze up” you couldn’t really do much
else with it. At the time, computer hardware was pretty limited, it had a single CPU core 
(something that executes instruction sets) which did pretty much everything, one by one - computer scientists were not particularly 
satisfied with this, and they [found a solution](https://en.wikipedia.org/wiki/Mutual_exclusion). 

In essence, execution of two or more computations is possible - given it is guaranteed that both read
data from the same source, but writing could lead to inconsistency - commonly known as a _data race_ or _race condition_. 
Today our computers have multiple cores - they can do a lot more stuff than they [used to](https://en.wikipedia.org/wiki/Moore%27s_law), 
but we need some way to guarantee or make it really hard for this to happen.

The world of concurrency is fascinating, lots of languages design mechanisms around this problem known as 
**concurrency primitives**, allowing software creators to fashion applications and software systems that perform much better
than their sequential alternative, however we are most interested in a cursory glance into the BEAM 
(Erlang’s virtual machine). For brief context, a virtual machine is just software - an abstraction over the basic
hardware of a computer allowing a layer of execution on top of it. 
The elixir/erlang source code is parsed and transformed into a set of intermediary files prefixed with `.beam` that the 
virtual machine can understand known as bytecode, via the `C` programming language. From here it is translated into 
assembly/machine instructions, 1's and 0's.


**source code**  --->  **c interface** --->  **bytecode**

Most of the interesting [concurrency primitives](https://en.wikipedia.org/wiki/Actor_model) that erlang/elixir provide 
are built on top of the [guarantees](https://ferd.ca/it-s-about-the-guarantees.html) this virtual machine provides such
as immutable state. The single basic unit being a process - 
an isolated sequential unit of computation which is managed by a scheduler an important construct.

### Erlang’s scheduler

The scheduler within the BEAM runtime (not an [operating system scheduler](https://en.wikipedia.org/wiki/Scheduling_(computing))),
talks to the operating system via [threads](https://www.cs.uic.edu/~jbell/CourseNotes/OperatingSystems/4_Threads.html) and 
manages the [how and when](https://hamidreza-s.github.io/erlang/scheduling/real-time/preemptive/migration/2016/02/09/erlang-scheduler-details.html)
of computations (processes - in the vm). It does something called preemptive scheduling which requires making
a nuanced trade off - all processes are treated as equal and given a tiny block of time/memory to execute, whether this
is enough for a process is irrelevant. It sacrifices the efficient allocation of resources to processes that need it most
to make some important guarantees which make fault tolerance possible:

1. High availability
2. Isolated failure states

This constant _context switching_ gives guarantees creating a system that is dependable - allowing the creation
of processes that inspect others, we can leverage this information to make intelligent deductions about what is happening 
within the system at runtime and design strategies to deal with and understand crashes and fail states, 
while also providing concurrent primitives that naturally scale across distributed systems, 
changing very little about the core system.

![Observer showing scheduling](/observer.png)

### Scheduling Processes
You can see the scheduler at work by spinning up a few short-lived processes which begin their life time with about 
two kilobytes of memory which can grow on a:
1. stack
2. heap

Here you have the parent process creating another process that sends it messages:
```elixir
# the current parent process's identifier
current = self()

child = spawn(fn -> 
  send(current, {
    # child indentifier
    self(), 
    "computation"})
end)
```

some more for good measure:
```elixir
child_two = spawn(fn -> send(current, {self(), "computation two"}) end)
child_three = spawn(fn -> send(current, {self(), "computation three"}) end)
child_four = spawn(fn -> send(current, {self(), "computation four"}) end)
child_five = spawn(fn -> send(current, {self(), "computation five"}) end)
```

Processes have an `identity` via their `pid`, this is how they are aware of one another, when the scheduler(on one core) 
sees these concurrent tasks, it allocates some time and memory at runtime to `child` and lets it run for a bit, if the process does not
finish(an infinite loop for example), the scheduler moves on to `child_two` and so on, checking up on each process,
computing a bit. 

### It's all about tradeoffs
Elixir provides a beautiful modern language that allows you to leverage athe amazing ecosystem and novel concurrency ideas
built into erlang, this design offers you tools and design to create highly fault-tolerant, self-healing systems, sometimes
at the cost of absolute runtime performance. You can see this with need to replicate data structures and performing 
computationally intensive tasks would make sense to be processed sequentially. Do not despair however, you can simply
outsource this kind of heavy-lifting if required to a service in a different language or carefully poke a hole into the
C interface via Native Implementation Functions, where in C++ or perhaps rust via [rustler](https://github.com/rusterlium/rustler).
