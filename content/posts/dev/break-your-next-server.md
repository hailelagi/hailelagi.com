---
title: 'Break your next server'
date: 2020-10-24T15:03:16.225Z
draft: false
tags: ['elixir', 'otp', 'concurrency', 'architecture']
original: "https://atimetravellingghost.wordpress.com/"
---

# Your friendly neighbourhood aspiring junior dev's guide to understanding the philosophy of fault tolerance in servers. A series of rants and odd thoughts.

I want to propose something, break your next server, on purpose. Nope that title isn't clickbait, but I hope you spare me a few moments to explain. Runtime errors are the last thing you want to happen in your code right? Especially if it's running in "production", but you know... I don't know.

I'd like to think in general software development, stuff goes wrong more than it goes right. I always wonder what happens in real software teams? how do they respond to minor and major corruptions in their systems? Servers break all the time. For lots of unusual reasons, *especially* in production. The world is a messy place, unpredictable and I have yet to find any real world service that hasn't experienced some sort of outage at some point in time. Sometimes? These are entirely unpredictable, novel problems that require novel solutions. There's no magic server that can guarantee 100% uptime(depends on what you define as "uptime", more on that later). Stuff happens, security vulnerabilities, scaling issues, dependencies on external services break, and so on. Things my inexperienced mind cannot begin to fathom.

Yet? sometimes, these errors aren't so unimaginable. A database query fails? oops! An external api endpoint gets stressed? (*cough graphQL) and the guys on the other side get a weird aws email? :frowning:, something gets deprecated somewhere and you forgot?

Okay, that's the *problem* what's the solution? Let's explore some common approaches before we know what exactly is going wrong. :smiling_imp:

## Deploy another one! (Modern problems require modern solutions!)
![gif of Bart and Lisa Simpson sitting on a couch](https://media.giphy.com/media/3o6Mbajy4stmeNfCPS/giphy.gif)
Apparently there's this fancy stuff they call a `container` these days. I won't bore you with infrastructure voodoo (I know little about it anyway), or less fancy a simple vcs checkout, let's keep this about *systemic approach* rather than implementation. These are different things, yes but they can be used(sometimes together or in isolation) to "fix errors". This approach says "oh crap" something broke, let's go back to *when it did work*. This is great except? Something caused a runtime exception you didn't expect and now you have an unavailable service. So you go off on an adventure, generating bug reports, pouring over log files and finding wtf happened! Sherlock mode activated! While this is happening you try to reboot the entire system with an older (bug free you believe) version. Nothing wrong with this, except? It's not solving the error problem. It's solving a dependency problem, an environment problem... but not necessarily an error problem and it's an approach at too high a level, you believe since the error happened in the programmer's domain? It must have been caused by it. Sometimes this is true, but not always. Sadly this server is too fragile anyway, just one lousy runtime error and everything goes boom?! You don't have to put yourself in that position. Not *unnecessarily* and *without good reason*. You should only need to re-deploy when something **really important** goes wrong. This should be a rare case.

## Avoid runtime errors at all costs!
![gif of Elliot Alderson on a train](https://media.giphy.com/media/l3YSeNYycfpIvPokM/giphy.gif)
At this point, we're jaded and cynical about I/O. Legend has it? If you wrapped your entire application in a try/except clause it will never fail. You have some input? Don't just sanitize it, you bleach it, add some disinfectant, rub some olive oil on it, cut a chicken's head off and invent scenarios. Likely? unlikely? doesn't matter! `try, except, catch, rescue` and their siblings are great... to a point. Yet, you can't predict every possible error under the sun. You need to take precaution, yes but you also need to be nimble, adaptable to the strange world of I/O and unpredictable side effects. The limitation of this approach is in the inability to isolate the error in the system, leading to generic uncaught exceptions and more importantly the corruption of state. More on that later. Depending on how this server's engineer intended recovery, it can go from beautifully crafted code to omg wtf is this because of the many paths the program can follow and how it re-converges to stability matters. This depends on skill and experience to execute and is a function of experience(usually) to the kinds of errors that could occur in prod. What if there was another way? Reflecting on experience is indispensable, you cannot substitute it. However, next best you can try to play catch up with a little foresight and study, re-inventing the wheel only when you need to.

## To be fore-compiled is to before tested!
![gif of anime girl typing quickly](https://media.giphy.com/media/kz6cm1kKle2MYkHtJF/giphy.gif)

There's this thing around the programmatic universe, it's called Test Driven Development. Some people swear by it, some think it's a pain, yet pretty much everyone thinks it's a good idea(except crazy people :smirk:). On another side of the equation you have static typing. What do these things have in common? They check for the correctness of software *before* it goes off into the real world(among other things lol). This is awesome, but it doesn't solve our problem still, how software behaves in an environment you do not control. These are lovely additions to controlling the programmer's domain and make sure(to an extent) nothing funny is going on through technology features and development practices.

## Embracing failure as an inevitable part of systems(and our lives) by introducing the horsemen of the error apocalypse, Agents, GenServers, Supervisors and Applications.
![cartoon dog sitting in a burning house](https://media.giphy.com/media/eIfYQTaK3148kmMCxT/giphy.gif)
There's a lovely rhetoric that I think holds true. Fail often, fail fast. Each of these approaches had a little something, a piece of the puzzle, a system design choice and when combined in the right way? they can be powerful tools. Introducing [fault tolerance 101](https://en.wikipedia.org/wiki/Fault_tolerance) which has a rich [history.](https://en.wikipedia.org/wiki/SAPO_(computer))

Fault tolerance and by extension concurrency are implemented in Elixir using the [Actor model](https://en.wikipedia.org/wiki/Actor_model). Let's start with the fundamental pieces and eventually how they work together to conceptually create an error tolerant server. You can ignore the code snippets if unfamiliar with the language, they run but are ultimately useless and illustrative. Before we go to the fun useful abstractions? Let's talk about the basics! Processes.

#### Processes
This one is weird, in that it shares the same name with a [system process](https://en.wikipedia.org/wiki/Process_(computing)). [Processes in Erlang/Elixir](https://elixir-lang.org/getting-started/processes.html) are lightweight spin offs that do stuff concurrently and communicate through messages. Sounds weird? Yup. I don't know much about how this is implemented internally(I'd love a pointer to deep dive resources). See Elixir is a functional language and yunno what that means kids! immutability, so how does concurrency happen? Why do we care? Well everything else is an abstraction built on top of this. You can think of a process like a *really really tiny server*, with the whole [request//response cycle](https://en.wikipedia.org/wiki/Request%E2%80%93response). This is what it looks like.

```Elixir
spawn fn -> "do something" end
```
*Doesn't this remind you of how a telephone line works?* Instead of a network you communicate with this lone wolf, through an `abstract mailbox` that holds messages in queue. Nothing complex here you `send` stuff and you `recieve` stuff. The mechanism is somewhat similar to `dispatching actions` in [redux](https://redux.js.org/) and this isn't a coincidence but a consequence of immutable state. I'll make references to redux, if you don't know it, that's fine. It's not a prerequisite. The high level concept is the main focus.

#### Agents
Here's where stuff gets interesting, now that we know what processes are, let's discuss something productive. Agents are essentially specialized processes that are used to store app state. If you know what a [redux store](https://redux.js.org/basics/store) is? this is a lot like that.
*Why is this useful?* you have some state that needs to be accessed by different parts of your application and most likely? these are going to be concurrent in different processes, how do you manage state? Agents are your goto solution. That's all it is, a safe space for your immutable state.

```Elixir
{:ok, store} = Agent.start_link fn -> "keep precious data safe" end
```
It has some useful APIs but we don't care about that right now, only the conceptual understanding of what it is and what it does. 

#### GenServers
Remember the analogy where I said you can think of processes as *really really tiny servers?* well there's a reason for that. A good mental model of this is anything that happens inside a process is the server and anything outside it? is the client. GenServers sound mystical the first time but it's actually short for a `generic server`.
```Elixir
defmodule MetalGearSolid do
  use GenServer
  # implement server
  @impl true
  def init(big_boss) do
    {:ok, big_boss}
  end
end
```
You can think of it as a "process that computes processes". This isn't as complex as it sounds. It just tells stuff what to do, it's like a jerk manager process that bosses around other developer processes...lol you just need to pass callbacks with the functionality you want the abstract `generic server` to have and you're done! Here's what it looks like.
```Elixir
  @impl true
  def handle_call(:snake, _from, [head | tail]) do
    {:reply, "#{head} becomes venom_snake spoiler!", tail}
  end
```
It holds application state(using a similar mechanism with agents), manages and monitors processes. You interact with it using sync `calls` and async `casts`. There is a little more boilerplate code but we don't care.

```Elixir
# Start the server
{:ok, pid} = GenServer.start_link(MetalGearSolid, [:naked_snake])
# client
GenServer.call(pid, :snake)
#returns ==> :naked_snake becomes venom_snake spoiler!
```
The [official Elixir guide](https://elixir-lang.org/getting-started/mix-otp/genserver.html) uses this phrase and it stuck with me "GenServer provides industrial strength functionality for building servers". That's an interesting choice of words, as someone who interned at a company that processes millions of dollars worth of product daily? Consider my interest piqued.
*Why is this useful though?* You see `genServers` are you bread and butter, this is what in essence computes all your lovely complex computations, network requests, database queries? you name it.

#### Supervisors(middle management)
![Cheryl Tunt from the show archer](https://media.giphy.com/media/g0vgklqMS8zT2/giphy.gif)
We can sorta intuitively understand processes and message passing. We've explored agents a safety net that make sure our state is never corrupted, and generic servers as abstractions that perform collections of necessary async processes... yet how is any of this fault tolerant?

What if we make a database query in a `genServer` and it fails?
Let's see what we have so far.
1. Our state isn't corrupted...great! (cause...immutability)
2. Functionality is isolated, but so what?
3. Our `genServer` is gonna start to panic. oh crap what do I do? It *knows* what's wrong and what is responsible. The process that was supposed to connect to the database failed...but now what?

What if you just need to try again? Maybe wait a little longer? Well now you need middle management, a faithful servant that will be there for you and observe what happens to your beautiful code and carries on your will when you can't.
```Elixir
children = [
  %{
    id: MetalGearSolid,
    start: {MetalGearSolid, :start_link, [[:naked_snake]]}
  }
]
# Make sure metalgear doesn't destroy the world
# here's the awesome strategy you apply
{:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)
```

#### Putting the pieces together as Applications
I've said a lot of stuff, all that was to prepare your mind. We can now talk about the [zen of Erlang](https://ferd.ca/the-zen-of-erlang.html) (you should really check out that article btw! it's really funny and imo communicates the point of this post). The philosophy of fault tolerance(OTP) is built on structures of processes, isolated pieces of functionality talking to each other, to make bigger "units". Sometimes? This functionality is `linked` other times? Our system can live without the database query knowledge of a user's favorite cat, this is how robustness is created. By identify mission critical parts of our system? We can protect them, even in the face of failing little bits and design strategies to cope. 

***The programmer becomes the ultimate creative ninja.***

We display our cool coding skills proudly in the world of I/O. Unafraid of what could go wrong because we know something probably will! Our strategies of recovery are a game, we can trace error points, cast out unnecessary operations, skip some? Restart entire groups of dependent process... the possibilities are endless! If you're wrong? then the supervision tree will continue to run with less and less functionality until the errors propagate far enough into the system(*now you have something to worry about and can apply strategy one!!!*) and even *here* you have time to figure out what is going horribly wrong, and more often than not? You probably should never have shipped that.

Applications are such large units of functionality in a larger system. Take a phoenix server, it's an application, the database query interface is child of the parent process, *even* the endpoints are children, what happens when part of the functionality stops? Internally? **The server will try to recover how I tell it to, using telemetry to report what happened, all the while still performing other functions** It's a thing of true beauty! The error(s) caused by any module are **independent** of any other part of the system.

In summary, agents store state, supervisors are co-ordinators, while genServers are executors and together they make up an application(which could also exist with them though). There are other interesting abstractions such as `Tasks`,`Registry` and `Dynamic Supervisors` the world of OTP is fascinating.

### GOTCHAS
Okay, you've read all about fault tolerance and how this can probably help you. The question remains... do you really need it? This is about an approach to solving software problems, you don't need Elixir/Erlang for this. An honorable mention is this [implementation in javascript](https://github.com/Akamaozu/node-supe) of a supervision tree. In fact, I'd go as far as to agree that [functional programming doesn't necessarily mean good software either!](https://degoes.net/articles/fp-is-not-the-answer). However Elixir/Erlang are extremely good tools optimised for not just dynamically handling errors in production but more importantly [handling lots of persistent concurrent connections up to two million apparently!](https://www.phoenixframework.org/blog/the-road-to-2-million-websocket-connections). This isn't just fluff either, [the whatsapp team achieved similar results in production way back in 2012 with Erlang](https://blog.whatsapp.com/1-million-is-so-2011) and [discord seems to love the language](https://blog.discord.com/how-discord-handles-push-request-bursts-of-over-a-million-per-minute-with-elixirs-genstage-8f899f0221b4?gi=d0cc90e81303). These features are baked into the core language and ecosystem because it optimizes for them, it's easy to fall into the pit of success and program with these things first and foremost in mind. Many programmers and companies use many different programming languages with differing paradigms and practices, whether this is the right choice isn't simple. Isn't that what's fun about engineering? Software or not. Almost every cool decision is lowkey a [constrained optimization problem.](https://en.wikipedia.org/wiki/Constrained_optimization)

1. Do you want to learn a new language and ecosystem? and dive into a completely new paradigm (assuming you're coming from a multi-paradigm or object oriented approach) It is an investment to think about.
2. Does your system *really* need high availability? Which is to say is [robustness an important feature you're optimising for?](https://www.robust-reliability.com/en/robust-design/robust-designb)
3. Do you need distributed computing?
4. Do you intend on having A LOT of clients that do stuff at the same time?
*(A chat app is a good example - see discord and whatsapp case studies)*
5. Do you have an existing codebase?
*(Is the ROI of migrating really worth it?)*
6. Can you find good people who use this?
*(Not really the most popular language out there and the disadvantages that come with that)*
7. Are you a junior? Or an aspiring junior like myself optimising for a job? Well... imo you're out of luck with Erlang/Elixir. Sad fact is whatever few jobs that are available? Are probably beyond your experience level :( sorry.

Many many more questions remain to be answered for your particular use case. However, despite these things, I believe this is an excellent introduction and learning experience, to a fundamentally different approach to solving software problems using functional programming and understanding a curious model for achieving concurrency.

### Going Forward

- I'm looking to explore interesting technology. Stuff that's awesome because it's awesome. I have my eye out on [Julia](https://julialang.org/) and it's uses for my research project(if schools ever resume :( ) and [Go](https://golang.org/) for making tools. Got resource recommendations? not necessarily limited to languages, I'd love to hear them(web and scientific domains mostly!)

- I'm looking for really nice medium to large open source projects or fun hacks that are friendly. I have a lot of free time I'd like to spend hacking at stuff that *will be useful to people* and while trying to do this on my own is fine, it has limitations.

- Thank you for your time. I'm open to feedback whether in the form of criticisms, improvements or simply conversation, here on dev or anywhere you can find me on the internet :)