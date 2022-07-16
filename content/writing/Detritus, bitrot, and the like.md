---
title: "Detritus, Bitrot, and the Like"
date: 2021-08-18T10:28:54+01:00
draft: false
---

The title of this essay is inspired by [Deekoo](https://deekoo.net/technocracy/detritus.html) - seeing as I'm currently
trying to shake a sort of intellectual [bit rot](http://www.catb.org/jargon/html/B/bit-rot.html) in my mind and software projects.
This of course is owing to the fact that I'm a freshly minted graduate who hasn't written nor learnt seriously about software in perhaps
several months. I have no idea what to do next, I've lost that little spark of curiosity I once had for diving head first
into vast bodies of knowledge and loving it. Perhaps it'll helps to look back, analyse the things that went well, and the
things that did not and perhaps extract some useful knowledge to share about my own experience and context writing software
and sometimes with other people.

### The Problem of Rational Behavior
In order to solve problems and increase utility, humans throw resources at a problem. We exist bound by a conscious
stream of experiences relative to events, so in order to proceed with an action we bind it to a decision space, an
abstraction of our actions relative to our percieved environment and we make choices often unideal.

> The individual who attempts to obtain these respective maxima is also said to act "rationally." But it may safely be
> stated that there exists, at present, no satisfactory treatment of the question of rational behavior.
> There may, for example, exist several ways by which to reach the optimum position; they may depend upon the knowledge
> and understanding which the individual has and upon the paths of action open to him.

I have struggled with this. Switching my environment to school, introduced variability in my ability to create process and
habit. Electricity is sparse and inconsistent, Internet barely functional and sometimes non-existent, and the time management
crisis of writing good production software(on time) and keeping up with my degree's requirements (lectures, classes, assignments, exams _etcetera_)
proved to be an impossible problem. I tried of course - many things, the only important fact is they didn't work.

![Thats Too Much Man Sarah Lynn GIF](https://c.tenor.com/VoxJONDntsoAAAAC/thats-too-much-man-sarah-lynn.gif)

The solution I think, if anyone else happens to be faced with similar circumstances is to do "what you can with what you have",
but ultimately you cannot do your best work without critical infrastructure, inevitably your output cannot be optimal.
Entering "flow" will become a struggle and every action a chore. Switch environments if you can, if you cannot like I
could not, grin and bear the boredom and frustration of being unable to work on the things you want to work on. We are not products of our environment - I'd like to believe, but it'd be foolish to disregard it's influence.

### Effective Research
Writing logic is one of the few things purely in your control, therefore it is the easiest thing to accomplish. Do it last.
Which is ironic no? Since that is what is asked of you. First comes research. Extensive research, thorough research.
You need to have a proper mental model before you open your IDE. This is the thing most outside your control.
It involves synchronous and asynchronous communication with people, documentation, tickets _etc_.

All the pieces are not in one place, you must first architect(what should I be doing exactly?), then think of test cases
(how should this work, *if* it works? how do I know it works?), then implement (how it *actually* works).

If possible, read the codebase and relevant internal documentation if you have it. Read and re-read most of the codebase
 relating, understand the context of the task. Ignore how it's supposed to work. Then return to the task, re-read.
 Understand it in all of its technical glorious detail.

### Designing Programs
Allocate more time at the beginning of a task assignment purely to design. Delay writing logic for as long as possible.
This sentiment is important to repeat, I know the temptation is great, it seems an action bias is often the cure for
decision paralysis but this is not always the case. Understanding this balance especially if you're inexperienced like I
am is tricky. You think I need to start working on this as quickly as possible, fixed time, fixed constraints or so the
saying goes. This (often) leads to inefficiency in process as I've discovered first hand. You're either implementing the
wrong thing that works? Or you're implementing something that doesn't work how it's supposed to.

This will delay you in the future as you write tests that break the stupid thing and leave you in a worse off position.

When you have a sufficient mental model of a problem and its intended behaviour, you need to think carefully about the
possible solutions to what you're doing and how what you're doing fits into what existed before. Code bases grow very
big over time. Reducing the size and abstracting away complexity is always a good thing.

### The menace that is testing
Then tests. Yes, yes. I know you hate writing tests(perhaps you don't, idk) Often in my experience? Tests are hard to
write, because the codebase is already written, lots of moving parts that work together. Simple functions are easy to test.
You know how it's supposed to work. God even better it's a functional codebase. I love pure functions.
They're easiest to reason about. Easiest to test. Easiest to find edge cases. :)

Often the functionality to be included is in a mess of what the fuck is happening (TCP/IP network calls, mutations in dependents
that have dependents, unkown state of side effects). Expanding functionality is harder (generally) to test and to reason about. Even if
the addition seems trivial. More moving parts, and how those moving parts are supposed to talk to this new moving part
requires you understand how the parts moved before.

Not to mention that tests _are hardly ever reviewed_ for changes. Nobody
cares about tests, only they are there and they encompass some scope, extensive tests show that something works, **not how it doesn't**.

### On Code reviews
Code reviews are not personal. This is(was) a hard one for me. The point is to find problems. Detach yourself from your
code. Which is hard. Yet, you must learn that software evolves and grows, the expression is about contribution to a
collective, the goal is functionality and merged into production. The goal is to help your team. Not being right.
Consistency in a codebase is > than accuracy (or whatever you think is right or why). As a rule defer to a reviewer
unless there's an important reason why not. Changing that loop to a map won't kill you, large elements of reviews often
are opinionated, being the least opinionated person in this discussion is better for you not worse. More often than not
your reviewer has to maintain the codebase long after (potentially) you're gone, reviews help catch a lot of things you might
not have seen, but often not. For the times they're just opinionated fluff. Don't argue it.

Software is imperfect, the people who write it are imperfect. We write shitty software, but we shouldn't. Do better,
learn, grow. People that write interesting software seem not to care for what you know, but for the potential to absorb
large useful amounts of information and create useful things with that(with other people). Previous knowledge is an indication of this but
honestly who knows how to separate signal from noise? Seemingly this is driven by some internal curiosity aligning with
the problem space these group of people are trying to hack at, and they'd be glad to pay your rent and coffee to help them.

### On pace
My experience in the software industry was at a young cryptocurrency exchange building around ever-changing financial regulation
and finding product-market-fit. This means? Deadlines are tight. Things change rapidly. The government wakes up one day,
and a major part of the code base is deprecated without warning. Another morning a major service provider is down.
The pace is... something. The code base evolves as quickly as the volatile environment around it. I understand the
necessity, it must evolve otherwise death. Luckily had more experienced engineers who helped me navigate some of this.
Everything is urgent and important, tomorrow can mean wondering if you'll be homeless in six months, but it's exciting
in a way I think. High stakes, high rewards. The reward for doing good work is compounded over time, but the flip side
is making too many mistakes can cost you. Something to think about.

Pace is about forming good process. Every time you do it you can accelerate how quickly you do it and building tolerance
with the variations by keepingf of con, but often your responsibilities grow proportionally to what you can be assigned therefore each sprint you
must optimise it. The more that can be shifted to your plate (and accomplished...) the more that will be.

### On communication and estimates

Over commit to communication with other human beings. The more the better. Schedule in time for this, because it can be unpredictable how much overhead
this costs. No one _really_ likes meetings honestly, but humans have yet to figure out the orchestration problem of translating complex ideas and actions to other human beings so they can act on this information. This intersects with the problem of estimations. Estimations are notoriously hard, because when an idea is first formed in the mind it does not come with it constraints bounded in _actuality_. It is but an _abstract possibility_ of how deeply you understand the interplay of a system. Improving your knowledge of said system (experience within a domain), helps but ultimately the only way to know how long a task will take is by performing the act itself bound in _actuality_._Oh! how I wish I were a 10x engineer,a surgeon with the accuracy and precision of a needle and the speed of a fox. Oh! how I wish, but I am naught but a mere
mortal. Limitations are good but rarely is a task properly estimated. The impact of experience is overestimated :) in my opinion.

### Finally, on direction

> It is not a matter of exposing one's unchanging identity, the
> true self that has always been, but a way of exposing one's
> ceaseless growth, the dynamic self that has yet to be. 

Now, more than ever I feel lost, wheter it's trying to understand mathematics as it applies to finance, or perhaps diving even further into the weird world of the metaverse, the ever evolving ideas and complexity of understanding the bitcoin and ethereum eco-systems. Or perhaps it's even a deeper dive into understanding computer science & programming - networks? Maybe diving into [CTF's](https://en.wikipedia.org/wiki/Capture_the_flag#Computer_security), or perhaps it's none of these perhaps - its understanding game theory - melding mathematics with economics. idk.

Perhaps I'm [ngmi](https://www.uxsequence.io/news/blockchain-dictionary-a-z/)

I don't really have to know, I'll just figure it out as I go and see what happens, I'll be here figuring this life and software thing out :)