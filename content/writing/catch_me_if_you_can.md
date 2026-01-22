---
title: "Catch Me If You Can"
date: 2026-01-22T11:29:47+01:00
tags: python, llms, computer-architecture
draft: true
---

Unlike most people in the software industry, I don't know what to make of the impact of large language models on software development. I generally [believe there's some sort of a bubble but I have a negative bias](https://www.wired.com/story/mark-zuckerberg-meta-offer-top-ai-talent-300-million/), I still type out code, I use LLMs to ask questions and generate what I feel lazy about learning, but I don't really think it helps me beyond streamlining what is essentially a search/discoverability problem, because by and large even if it is knowledgeable and capable -- I am still forced to reason through difficult concepts, navigate abstraction layers, read code, validate and understand it, wheter it's generated or not -- which is sadly the bottleneck as I experience it?

I'm not blind to how it's changing what productivity means, the conversation is inescapable, and maybe I'll be left behind in the ever relentless chase, maybe I need to try out the latest models and shell out for yet another subscription? trying out claude code is very much on my todo.

Which brings us to a random thursday morning, I come across Anthropic's blogpost on [designing AI resistant technical evaluations](https://www.anthropic.com/engineering/AI-resistant-technical-evaluations), which was a nice instructive distraction from the apply-form-filling/leetcode/interview prep cycle that has come to dominate my sad and depressing life. 

{{% callout %}}
Given a task/topic/problem I know I <b>cannot do now</b> and knowing Claude is definitely better than I am, given enough time can I go beyond Claude's ceiling?
{{% /callout %}}

My background in a previous life now forgotten was in a STEM/chemical engineering degree, then I taught myself to program and I've since tried to learn as much as I can about web servers, databases and distributed systems. On honest reflection I would never claim understanding enough of these things but I try to reason through basics and do useful things, sometimes I succeed, sometimes I fail. However, I've retained a blindside for computer architecture - until now?

## The problem
We are presented with a simulation of a computation kernel and are tasked with optimizing the kernel as much as possible in the available time, as measured by test_kernel_cycles on a frozen separate copy of the simulator.

```bash
➜  original_performance_takehome git:(main) python3 tests/submission_tests.py
Testing forest_height=10, rounds=16, batch_size=256
CYCLES:  147734
Testing forest_height=10, rounds=16, batch_size=256
CYCLES:  147734
Testing forest_height=10, rounds=16, batch_size=256
CYCLES:  147734
Testing forest_height=10, rounds=16, batch_size=256
CYCLES:  147734
Testing forest_height=10, rounds=16, batch_size=256
CYCLES:  147734
Testing forest_height=10, rounds=16, batch_size=256
CYCLES:  147734
Testing forest_height=10, rounds=16, batch_size=256
CYCLES:  147734
Testing forest_height=10, rounds=16, batch_size=256
CYCLES:  147734
.Testing forest_height=10, rounds=16, batch_size=256
CYCLES:  147734
```

## Putting the "Me" in CP-You

What's a computer anyway? It kind of depends on your perspective, [this is a funny and great concise read,](https://cpu.land/) however for Anthropic's performance engineering challenge, the fundamental unit isn't a vertex, or a "node" or a VM process/thread, it's something I have genuinely taken for granted all my life it's a CPU.

## How Did You Pass The BAAAAAr'? Frank Abagnale Jr. ...

{{< youtube c9Uu7sxScYo >}}

