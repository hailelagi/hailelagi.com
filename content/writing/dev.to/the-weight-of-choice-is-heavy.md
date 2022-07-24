---
title: 'The weight of choice is heavy'
date: 2020-08-31T18:46:19.202Z
draft: false
tags: ['python', 'algorithms', 'probability', 'elixir']
original: "https://dev.to/haile/the-weight-of-choice-is-heavy-55o"
recommend: true
---

What are the odds? I've spent quite a few hours invested in implementing a seemingly innocent feature of a game I'm 
currently working on as part of my learning in the world of functional programming with Elixir. I won't bore you with
the details, I haven't even finished making the game, the prelude to discovering this problem is an innocent one.
It's a  terminal dungeon crawling game, where you venture into dark rooms in search of treasure and an eventual (hopeful) exit. 

The probability of choosing a room is controlled by a call to `Enum.random(iterable)` which selects a random element 
from the iterable, using Erlang's internal pseudo-random generation algorithm. At this point in time, only three rooms 
existed (a room leading to the exit, A room full of monsters and another room full of monsters.)
Therefore it's safe to *assume* the mathematical probability of finding any room is P(1/3). This isn't so great is it? 
You could just start the game and one-third of the time, without experiencing even a single battle :( 
Oh I know the author suggests... let's add different probabilities to the rooms, such that rooms with battles appear 
more likely and rooms with an exit less likely. Okay... so I tried it, after the first hour or so I came up with a
satisfactory(to me I thought) solution. This is it. I first added a probability key, with a value of an array of atoms to the struct.

```Elixir
defmodule DungeonCrawl.Room do
  @moduledoc """
  data structure representing a "room"
  a room has "actions" borrowed
  """
  alias DungeonCrawl.Room, as: Room
  alias DungeonCrawl.Room.Triggers, as: Triggers
  import DungeonCrawl.Room.Action

  defstruct name: nil, description: nil, actions: [], trigger: nil, probability: nil

  def all,
    do: [
      %Room{
        name: :exit,
        description: "You can see a small light from a crack in the walls",
        actions: [forward()],
        trigger: Triggers.Exit,
        probability: [:exit]
      },
    %Room{
        name: :goblin,
        description: "You can see an enemy blocking your path",
        actions: [forward()],
        trigger: Triggers.Enemy,
        probability: [:goblin, :goblin, :goblin, :goblin, :goblin]
      },
    %Room{
        name: :ogre,
        description: "Something moves around in the dark, what do you do?",
        actions: [forward()],
        trigger: Triggers.Enemy,
        probability: [:ogre, :ogre, :ogre]
      },
    ]
end
```
At once you can probably see the naiveness of this solution. What computed the algorithm is this
```Elixir
 defp bias_probability(rooms) do
    rooms
    |> Enum.map(fn room -> room.probability end)
    |> Enum.reduce(fn room, acc -> room ++ acc end)
    |> Enum.random()
  end
```
and finally now that I know the biased random outcome-
```Elixir
    rooms
    |> Enum.find(fn room -> room.name == bias_probability(rooms) end)
```
Technically? This is a mathematically correct solution. It will compute a random value with a biased probability of 
`P(0.1, 0.5, 0.3)`. I felt happy with myself, turned off my laptop and went to sleep! That was that! Or so I thought.

See there are two fundamental flaws of this approach:
1. *I'm hard coding the probabilities, although modifying the probability of a room is possible, it will result in
boiler plate code and unnecessary list traversal*

2. *The algorithm is not performant(in space complexity) atoms are not garbage collected in Elixir, and it would be 
unwise to arbitrarily create them on a whim! suppose I had a thousand rooms in the future for example*

Sure enough, extra feature requirements came, the addition of a "difficulty level" that will bias this probability 
dynamically. So.. began my search, with a renewed courage to try mathematical problems I tweaked and tweaked, no luck. 
I asked my friends in engineering from school no luck! and then sure enough, a friend of mine with superior googling 
skill found a long lost blog post from 2017. This is what really helped me, without it I was lost in meaningless 
scribbles of probability theory and conditional problems. If you're interested in learning more about implementing a 
weighted probability algorithm please check out [David Hills's blog](https://blog.bruce-hill.com/a-faster-weighted-random-choice) 
it's really detailed and well done! I'll focus on implementing two algorithmic approaches I learned and adapting it to 
the context of this game. The linear search and one of the alias algorithms.

## Probabilities can be unfair!

### Linear scan the O(kay) method
*O(n) runtime*

A lovely idea is to search the linked list for an index value based on probable outcomes, wish I thought of this!! 
This will work by generating a random number between `0 - 1` and multiply that by the total probability distribution
(For my use case, I'm assuming the list is sorted), then traverse the probability distribution subtracting each 
probability from the random probability, if it goes below zero? We've exhausted the probability distribution and 
found the index we need. Lovely solution. This works because we mathematically assume `random.random()` 
will generate a perfectly random number(spoiler it doesn't, but we don't care). If the probability is really low? 
It will hit the lowest index less often, and if the probability is high? It will hit that index more often. Run the code
below to get a sense of it if you like.

```python
import random

def weighted_random(weights):
    """
    INPUT probabilities - [0.2, 0.3, 0.5]
    OUTPUT index of random_weight - [0, 1, 2]
    """
    remaining_distance = random.random() * sum(weights)
    # probability distribution sample size * random integer
    for (i, weight) in enumerate(weights):
        # [{0, 0.2}, {1, 0.3}, {2, 0.5}]
        remaining_distance -= weights[i]
        #print("debug", remaining_distance)
        if remaining_distance < 0:
            return i

# Repeat the experiment to observe bias factor
for e in range(10):
  print(f"exp trial{e}",weighted_random([0.2, 0.3, 0.5]))
```

This seems really cool doesn't it? I can represent the P(n) of my game as floats and dynamically update them, 
keeping the purity of the function. A quick and dirty Elixir version of this looks like

```Elixir
defmodule Prob do
  def bias_probability(weights) do
    # [i[0] P=0.2, i[1] P=0.5 , i[2] P=0.3] s.s = 3
    # P(n) = distribution sample len bias * random() - P[i] < 0
    len = Enum.count(weights)
    # could increase range for greater float precision as you like
    distance = Enum.random(1..99)/100 * Enum.sum(weights)
    # bias factor
    enumerated_list = Enum.zip(0..len, weights)

    Enum.reduce_while(enumerated_list, distance, fn (_weight = {i, w}, acc) ->
      if (acc - w) > 0, do: {:cont, acc - w}, else: {:halt, i}
    end)
  end
end

IO.inspect Prob.bias_probability([0.2, 0.3, 0.5])
```
and then to find the biased index.
```Elixir
    rooms
    |> Enum.map(fn room -> room.probability end)
    |> Enum.fetch(bias_probability(rooms))
```

but now that I've gone through the trouble of investigating weighted probability, I don't wanna settle for a linear search. Might as well make the game with the fastest possible approach. Let's go back in history, and take a look at one of the [alias algorithms](https://en.wikipedia.org/wiki/Alias_method).

### Aliasing(Vose) the O yes! method
*O(n) alias table prep + O(1) lookup*

This one is a bit tricky to understand at first. If you're interested in a much more technical deep dive into the various
approaches for solving this problem, please check out this [article by Keith Schwarz](https://www.keithschwarz.com/darts-dice-coins/) 
it's dense, comprehensive and technical. Onto aliasing!

The idea is honestly very clever! and in my opinion counter-intuitive, which is what makes it's constant-time runtime 
lookup so impressive. Let's take a step back, before diving in. An alias is like a nickname we give to stuff right? 
You have a friend called Samuel, and you call him Sam. His name isn't Sam and he hates that nickname, but alas, it 
stuck... poor Samuel, but if you see his face anywhere you know Sam is Samuel because you're such good friends. 
The alias method is a lot like this in principle. You have a biased probability weight distribution and it 
*approaches some limit* and that limit can be used to generate a custom distribution. Let's talk about Sam for a bit.

See Sam's nickname is called an `alias table` and your friendship(how you know Sam is Samuel) is the algorithm.
Now that we have some hint as to what we're doing, here's the python implementation with my comments from Bruce Hill's blog.
Scan through it, maybe run it if you're adventurous. We'll break it down step by step next. 
(If you're familiar with Java check out [Keith Schwarz's implementation instead](https://www.keithschwarz.com/interesting/code/?dir=alias-method)

```python
def prepare_aliased_randomizer(weights):
    N = len(weights) # limit
    avg = sum(weights)/N # alias partition

    aliases = [(1, None)] * N
    # [(1, None), (1, None), (1, None)] --> alias table

    # Bucketting (pseudo quick sort like behaviour*)
    # weight/avg < | > avg
    # smalls are partial alias fits
    # bigs fits and remainder thrown to smalls

    smalls = ((i, w/avg) for (i, w) in enumerate(weights) if w < avg)
    bigs = ((i, w/avg) for (i, w) in enumerate(weights) if w >= avg)

    # [(0, 0.6), (1, 0.9)] --> small weight avgs
    # [(2, 1.5)] --> big weight avgs
    #cycle through small and big partition generator
    small, big = next(smalls, None), next(bigs, None)

    # if elems are not exhauted kindly loop
    while big and small:
        # put the partial elem in aliases
        aliases[small[0]] = (small[1], big[0])
        print("alias lookup table transformation", aliases)

        # big = i of big , weight_b - (1 - weight_s)
        # big = (0, (1.5 - (1 - 0.6))
        big = (big[0], big[1] - (1-small[1]))
        if big[1] < 1:
            print("large weight is < 1 skip", aliases)
            small = big
            big = next(bigs, None)
        else:
            small = next(smalls, None)

    print("alias table generated", aliases)
    # SELECTION STAGE
    def weighted_random():
        r = random.random() * N
        i = int(r)
        # choose a random probability
        # from the alias table
        (odds, alias) = aliases[i]
        print("what are the odds of", r)
        # return the larger probability if
        # it's odds are higher else
        # return the smaller probability index
        return alias if (r-i) > odds else i
        
    return weighted_random()

# single trial selection
print(f"experiment trial", prepare_aliased_randomizer([ 0.2, 0.3, 0.]))

# Repeat the experiment to observe bias factor
for e in range(10):
  print(f"experiment trial", prepare_aliased_randomizer([0.2, 0.3, 0.5]))
```
PHEWW!!!!!!! there's alot going on. Let's break it down. There are two major steps, once you understand how the table is
generated(that's most of the work) the lookup naturally follows.

***This paragraph is interesting but ultimately a digression, you can choose to skip over it!***
*How exactly does a computer remember who Sam is? Well computers are a little like the human brain, people have complex organic circuitry of neurons that consolidate sensory observation and from that recognizes patterns and form "thoughts", the only difference is we have to tell the computer what pattern it should follow and it doesn't necessary form a thought, simply a result, and we do not need such instructions?(dna? nope, it's a philosophical question of not only intelligence but implicitly will :) does existence precede essence? I like to think so. Shameless plug, @ me on [twitter](https://twitter.com/haile_lagi) if you're interested in this topic).*

#### Table generation

To create the table, the original weight distribution is sliced into pieces(partitions)! Quite literally! Suppose we
know how many weights we need, in this case 3, that's the limit. To find `P(0.2, 0.3, 0.5)` We create an empty alias,
with a data structure, with the exact same length `[partition, partition, partition]` and a probability 
`[partition, partition, partition]`. Each partition will contain exactly `P(1/3)`. Here's the interesting part, we then
scale the probabilities to the factor of our limit and separate it into chunks `less than 1` and `greater than or equal to 1`. Why?

Here is the rationale:
1. If the weight fraction is greater than one or equal to it, it will fill a single alias partition(fit exactly if equal else)
with some change! which will be sent to an empty partition.

2. If the weight is less than one, then it will be smaller than the allocated partition and it will be expecting a buddy :)

Each partition, will hold a new distribution perfectly and why this is mathematically correct.. is kinda funny tbh.
I won't discuss the formal proof, but the idea is that at any point in time, the sum of the elements in the distribution
is always proportionate to the original weight.

```Elixir
defmodule Probability do
  def bias_probability(weights) do
    # Initialization
    n = Enum.count(weights)
    prepare_alias_table(weights, n)
  end

  defp prepare_alias_table(weights, n) do
    alias_table = Enum.map(1..n, fn _ -> {0, nil} end)
    prob = Enum.map(1..n, fn _ -> nil end)

    # create work lists
    scaled_weight = scale_probability(weights, n)
    small =
      scaled_weight
      |> Enum.filter(fn {_, w} -> w < 1 end)

    large =
      scaled_weight
      |> Enum.filter(fn {_, w} -> w >= 1 end)

    # recursively create table (TCO optimized)
    transform_alias(small, large, alias_table, prob)
  end

  # Base case when small and large are empty
  defp transform_alias([], [], _, prob), do: prob

  defp transform_alias(small = [], [_g = {i, _} | tail], alias_table, prob) do
    # Remove the first element from large call it g, Set prob[g] = 1
    transform_alias(
      small,
      tail,
      alias_table,
      List.replace_at(prob, i, 1)
    )
  end

  defp transform_alias([_l = {i, _} | tail], large = [], alias_table, prob) do
    # (clause will trigger due to numerical instability)
    # Remove the first element from Small, call it l
    transform_alias(
      tail,
      large,
      alias_table,
      List.replace_at(prob, i, 1)
    )
  end

  defp transform_alias(
         [{index_l, weight_l} | tail_s],
         [_g = {index_g, weight_g} | tail_l],
         alias_table,
         prob
       ) do
    # Remove the first element from small call it l
    # Remove the first element from large call it g
    # Pg := (pg + pl) - 1 (numerical stability :) )
    new_weight_g = (weight_g + weight_l) - 1

    # if Pg < 1 add g to small
    if new_weight_g < 1 do
      transform_alias(
        [{index_g, new_weight_g} | tail_s],
        tail_l,
        List.replace_at(alias_table, index_l, weight_g),
        List.replace_at(prob, index_l, weight_l)
      )

      # else Pg >= 1 add g to large
    else
      transform_alias(
        tail_s,
        [{index_g, new_weight_g} | tail_l],
        List.replace_at(alias_table, index_l, weight_g),
        List.replace_at(prob, index_l, weight_l)
      )
    end
  end
  # HELPER
  defp scale_probability(probs, n) do
    0..n
    |> Enum.zip(probs)
    |> Stream.map(fn {i, w} -> {i, w * n} end)
  end
end
```

Now that we can generate an alias table, this implementation will also include a local cache using 
[Erlang Term Storage](http://erlang.org/doc/man/ets.html) to hold the alias table inside another table!
throughout the lifecycle of the application once it has begun to run. I'm assuming once a difficulty level is selected
random rooms need to be populated but the probability of that room occuring needs to be computed once.

```Elixir
  def bias_probability(weights) do
    # Initialization
    # does the probability exist in memory?
    current_probability = try do
      [weights: cached_probs] = :ets.lookup(:weight_probability, :weights)
      cached_probs
    rescue
      ArgumentError -> cache(weights)
    end

    current_probability
    #|> weighted_random # to be implemented next
  end

  defp cache(weights) do
    n = Enum.count(weights)
    :ets.new(:weight_probability, [:duplicate_bag, :private, :named_table])
    :ets.insert(:weight_probability, {:weights, prepare_alias_table(weights, n)})
    [weights: cached_probs] = :ets.lookup(:weight_probability, :weights)
    cached_probs
  end
```

#### Look up

Finally we can generate a random probability and select an index to return from it!

```Elixir
  # GENERATION
  defp weighted_random(aliased_table, n) do
    # Generate a fair random distro in a range
    # from n and call it i.
    r = Enum.random(0..1000)/1000 * n
    # random choice P(1/3)
    i = floor(r) # 0, 1 , 2

    prob = aliased_table

    {:ok, odd} = Enum.fetch(prob, i)

    # partial fit
    if (r - i) > (odd) do
      # which piece of what goes where
      bias = prob
      |> Enum.with_index()
      |> Stream.filter(fn {p, _} -> p == 1 end)
      |> Enum.random()

      {_, i} = bias

      i
    else
       i
    end
  end
```

Here's the whole implementation in a [Github gist](https://gist.github.com/hailelagi/553d0af87209f21516be8fb53bcdf453)

## GOTCHAS
There are quite a few waiting for you if you desire to copy/paste this implementation, for example I ignored float 
point precision(somewhat) instead I could have chosen to seed the values and *my probabilities are always weight fractions of 1*, 
or the implicit assumption of never returning 0, or 1 weights in the linear search. Please read the more indepth blogs,
they're invaluable. For my use case though, it could probably scale to thousands of rooms effortlessly.

Thanks for reading!!! I'm always looking for feedback, have a suggestion? found a bug? Know an interesting algorithm? 
Maybe you just wanna leave kind words, I'm always happy to converse :)
