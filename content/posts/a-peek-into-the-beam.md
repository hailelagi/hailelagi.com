---
title: "A Peek Into the Beam"
date: 2022-03-02T08:16:09+01:00
draft: false
tags: go, python, elixir, erlang, scheduler, concurrency
---

A long time ago, you would give a computer an intensive set of instructions - in assembly or something more sane, and 
it would compute these instructions one by one, but while it did that - it would “freeze up” you couldn’t really do much
else with it. At the time, computer hardware was pretty limited, it had a single CPU core 
(something that executes instruction sets) which did pretty much everything, one by one - computer scientists were not particularly 
satisfied with this, and they [found a solution](https://en.wikipedia.org/wiki/Mutual_exclusion). 

In essence, execution of two or more computations is possible - given it is guaranteed that both read
data from the same source, but writing could lead to inconsistency, commonly known as a _data race_ or _race condition_. 
Today our computers have multiple cores - they can do a lot more stuff than they [used to](https://en.wikipedia.org/wiki/Moore%27s_law), 
but we need some way to guarantee or make it really hard for this to happen.

The world of concurrency is fascinating, lots of languages design mechanisms around this problem known as 
**concurrency primitives**, allowing software creators to fashion applications and software systems that perform much better
than their sequential alternative, however we are most interested in a cursory glance into the BEAM 
(Erlang’s virtual machine). For brief context, a virtual machine is just software - an abstraction over the basic
hardware of a computer allowing a layer of execution on top of it. A common example being the Java Virtual Machine (JVM).
The elixir/erlang source code is parsed and transformed into a set of intermediary files prefixed with `.beam` that the 
virtual machine can understand known as bytecode, via the `C` programming language. From here it is translated into 
assembly/machine instruction bits [[1]](#references).

**source code**  --->  **c interface** --->  **bytecode**

Most of the interesting [concurrency primitives](https://en.wikipedia.org/wiki/Actor_model) that erlang/elixir provide 
are built on top of the [guarantees](https://ferd.ca/it-s-about-the-guarantees.html) this virtual machine provides such
as immutable state. The single basic unit being a process [[2]](#references) [[3]](#references) - 
an isolated sequential unit of computation which is managed by a scheduler an important construct.
```
Note: you may think of a process as a kind of "green thread",
if familiar with the concept. Otherwise thinking of them
as an abstract unit of sequential computation is fine.
```

## Erlang’s scheduler

The scheduler within the BEAM runtime (not an [operating system scheduler](https://en.wikipedia.org/wiki/Scheduling_(computing))),
talks to the operating system via [threads](https://www.cs.uic.edu/~jbell/CourseNotes/OperatingSystems/4_Threads.html) and 
manages the [how and when](https://hamidreza-s.github.io/erlang/scheduling/real-time/preemptive/migration/2016/02/09/erlang-scheduler-details.html)
of computations (processes - in the vm). It does something called _preemptive scheduling_ which requires making
a nuanced trade off - all processes are treated as equal(unless a priority is set) and given a tiny block of time/memory
to execute, whether this is enough for a process is irrelevant. It sacrifices the efficient allocation of resources to
processes that need it most to make some important guarantees which make fault tolerance possible:

1. High availability
2. Isolated failure states

This constant _context switching_ gives guarantees creating a system that is dependable - allowing the creation
of processes that inspect others, we can leverage this information to make intelligent deductions about what is happening 
within the system at runtime and design strategies to deal with and understand crashes and fail states, 
while also providing concurrent primitives that naturally scale across distributed systems, 
changing very little about the core system. 

A typical illustration of erlang's introspective superpower is `:observer` which ships by default. Pop `:observer.start()` 
into any `iex` session and watch the magic.

```bash
user@my-pc $ iex
iex(1)> :observer.start()
```

![Observer showing scheduling](/observer.png)

You can see the scheduler at work by spinning up a few short-lived processes which begin their lifetime[[4]](#references) 
with about [326 words of memory](https://en.wikipedia.org/wiki/Word_(computer_architecture)) (approximately 0.65 kilobytes) 
which can [grow](https://www.erlang.org/doc/man/erts_alloc.html) on a stack or heap.

Here you have `self()` as the `iex` session process, creating another process that it communicates with:
```elixir
iex(1)> current = self()
iex(2)> child = spawn(fn -> 
  send(current, {
    # new identifier process created by spawn
    self(),
    # any arbitrary sequential computation
    # looping, control flow, anything :O
    1 + 1})
end)
```

We can then leverage the high level `Process` library for convenience, to create more processes, thousands or even millions
if need be:

```elixir
child_two = Process.spawn(fn -> 1 + 2 end, [:monitor])
child_three = Process.spawn(fn -> 1 + 3 end, [:monitor])
child_four = Process.spawn(fn -> 1 + 4 end, [:monitor])
child_five = Process.spawn(fn -> 1 + 5 end, [:monitor])
```

Processes have an `identity` via their `pid`, this is how they are aware of one another. The return value of each child 
looks a little like this:
```elixir
# {#PID<0.93.0>, #Reference<0.18808174.1939079169.202418>}
```
```
 Note: The actual pid and reference will be different on your machine).
```

When the scheduler(on one core) sees these concurrent tasks, it allocates some time and memory at runtime to `child` 
and lets it run for a bit, if the process does not finish(an infinite loop for example), the scheduler moves on to
`child_two` and so on, checking up on each process, computing a bit. Processes are namespaced in a 
[local registry](https://hexdocs.pm/elixir/1.13/Registry.html) for a single node. Scheduling across multiple nodes
works the same way, only you'd need a different way to [manage the global name space](https://github.com/uwiger/gproc)
of running processes.

### todo(useful comment): Restructure and answer these questions
**todo(useful notes): Expand on high availability and isolated failure states**
1. We don't interact with the CPU, which your article pointed out - we think “processe” -
   small, non-shared state and isolated failure. how to fault tolerance.

2. How do we handle shared resources in processes in Elixir - I'd suggest you focus on a “Genserver” as the ideal process/
Agent

3. How do we handle async failures? You can mention supervisors e.t.c

## It's all about tradeoffs
### (Multithreading vs Actor model vs CSP routines)

Elixir provides a beautiful modern language that allows you to leverage the amazing ecosystem and novel concurrency ideas
built into erlang, offering you the tools to create and design highly fault-tolerant, self-healing systems, sometimes
at the cost of _absolute runtime performance_. You can see this with need to replicate data structures and performing 
computationally intensive tasks that would make sense to be processed sequentially. Do not despair however, you can 
carefully poke a hole into the runtime through the C interface via 
[Native Implementation Functions](https://www.erlang.org/doc/tutorial/nif.html#:~:text=A%20NIF%20is%20a%20function,UNIX%2C%20DLL%20in%20Windows), 
whether in C++ or perhaps rust via [rustler](https://github.com/rusterlium/rustler). Or outsource this kind of 
heavy-lifting if required to a service in a different language. Let's explore at a high level the conceptual 
underpinnings of relatively more popular languages and how they stack up against the BEAM's approach.

### Actor Model vs Multithreading (Ruby, Javascript and Python)
# TODO Contrast
1. CPU interaction/scheduling/concurrency
   How is this done in ruby/js/py? Threads? What are the issues here? Deadlock, null pointer?
  comparable? short concise overview and contrast.

2. How do we handle shared resources in processes 

3. How do we handle async failures?


### Actor Model vs csp routines (goroutines)
1. CPU interaction/scheduling/concurrency
   goroutines what are the issues here? deadlock, null pointer?
   comparable? short concise overview and contrast.

2. How do we handle shared resources across nodes 
locks and mutexes

3. How do we handle async failures?

### Erlang processes vs the EVM model [bonus content - might not add to be decided]
EVM is a Single-Threaded state machine. [[6]](#references)

## References

[1] fxn(medium): https://medium.com/@fxn/how-does-elixir-compile-execute-code-c1b36c9ec8cf

[2] green threads(wikipedia): https://en.wikipedia.org/wiki/Green_threads

[3] Joe Armstrong(twitter): https://twitter.com/joeerl/status/1010485913393254401

[4] Erlang documentation: https://www.erlang.org/doc/reference_manual/processes.html

[5] Erlang documentation: https://www.erlang.org/doc/efficiency_guide/processes.html

[6] coinmonks(medium): https://medium.com/coinmonks/concurrency-and-parallelism-in-smart-contracts-part-1-10e8f6ecfa12


