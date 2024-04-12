---
title: 'Schrödinger, cats and boxes.'
date: 2020-07-26T17:20:14.864Z
draft: true
tags: ['functional', 'paradigm', 'agnostic', 'monads']
original: "https://dev.to/haile/schrodinger-cats-and-boxes-l93"
---

>“And the earth was without form, and void; and darkness was upon the face of the deep. And the Spirit of God moved upon the face of the waters.”
*Genesis 1:2*

If functional programming were a cat? It'd be a black cat. Cats are a lot like functional programming, herein referred affectionately to as fp. It's really more scared of you than you are of it. You see? it's always trying to find compile time guarantees and predictable data flow. It's a fragile thing this paradigm, it can't handle the real world of I/O on its own. It needs help from you the programmer and it begs you not to be stupid.

<img src="https://media0.giphy.com/media/7vhAnGwSOQvUQ/200w.webp?cid=ecf05e47d992e46e1fc6c67dbbc5153d0601d01dc14928d4&rid=200w.webp" width="480" height="270"></img>

Unlike their very flexible abstract brother in arms? Objects? They take abstraction and flip it on its head. Gone is the *natural*(familiarity bias) view of the programmatic universe, enters this dystopia! Filled with processes that lead to processes. I no longer see a Tree surrounded with air, I see photosynthesis!. The complexity of fp is meant to simplify programming not obscure it. It's scared of mutations! who wants to be a powerless human? among X-men? with the ability to simply create *new* data structures at will. They are more like a logicians wet dream. Pretty premises coming in to be analyzed with a scalpel of wit, to its rational valid conclusion. 

<img src="https://media2.giphy.com/media/j9EfZBLJsLIuA/giphy.webp?cid=ecf05e47bhv0d1v0y7w300d67cintcn9pmzbk23e1i15bfz8&rid=giphy.webp" width="480" height="270"></img>

*Once upon a time, long ago a man asked himself? What is a thing? Then the woes of all programmers began*

Let's leave programming for a little while. Follow Alice down this rabbit hole, I promise we will return. For now let's say hi to Oxford philosopher William of Occam, and the [modal theory](https://plato.stanford.edu/entries/modality-medieval). Not [Model theory](https://en.wikipedia.org/wiki/Model_theory) as is traditionally done. You see I am not passionate about mathematics, I tolerate its method for utility. Another noteworthy person of stature was Peter Abelard. There was a problem [plaguing](https://en.wikipedia.org/wiki/Black_Death) people in the middle Ages(pun intended) it was a problem of stuff. Nope not conspicuous consumption you of the bourgeois class :) What are stuff anyway? 

But first another digression from this digression! Forgive me! But we are looking back into history in the wrong order, and for good reason as you'll come to understand, I hope. Let's pay our respect to the mathematicians before we cast their headache inducing notations *ad nauseam* aside. To the original gangster himself, Wilhelm Leibniz. 

Yup that one, the calculus guy that ruined my engineering education(let's forget that other alchemist for now he isn't important). Curse these polyglot achievers, mere mortals like myself struggle in one field but calculus was not mathematical enquiry. Or at least it was not created to be "just" math. It was a pure expression of holy abstraction, to cut down any and all in every field(arguably it has somewhat achieved its intended goal). It is strange the first time you see it. dy/dx. Oh the PTSD this symbol brings back but *that is what it is* a **symbol**. A representation of the rate of change of relative quantities? Oh hush now, this has nothing to do with programming you complain! But it has everything to do with it. The pieces will align, eventually. I hope as I learn, I write and hope I do not err in communication.

You see? It is the fault of these men. Men like Goedel, Russel, Venn and Boole among others. They cursed us with genius and forgot to dumb it down. Before we return to modal theory let's dive into languages and symbols for a bit without going into too much overwhelming detail? This is what your everyday programmer does. A little `if` here, a little `false` there. Some iteration there to be sure, a little recursion here poof!!! you have yourself magic! But it wasn't always so. See there was a problem Leibniz attended to. When we speak or write we do so by conveying thoughts that have **cognitive meaning** or **emotive meaning**. Emotive statements tend to make a value claim here and there you know them, politics, morality, ethics, those tricky things. Logicians don't like those. They like statements that can be *evaluated*.
 
> The sky is black.

You can notice certain features - It's unambiguous and specific, the premise holds the subject "sky" and adds an adjective(attribute or qualifier) that makes a proposition. It gives you something to think about doesn't it? Suddenly you think of empirical research to support or dispute this. It makes a claim that can be true or false but never both nor neither.

Easy to reason about no? Now imagine "sky" was data. Could be an array of integers, could be a string of unicode characters. Let's add an attribute to it. Let's call it "black" or "green". Ahhh!!!! now you see it yes? Sky is an object. This is the object oriented approach but remember here? in a functional universe there are no objects like Leibniz let's think of it as dy/dx lol. Think of it like a *process*. A transformation of data that may or may not be true. All of a sudden you're asking `is_black(The sky)`.

**WTFFFFF!!!**

I said. Where is the sky coming from? `is_black` don't give AF. It *only* knows how to be black. The qualifier does not belong to the object, if you really think about it? It makes sense. Lot's of things can be black, you can have a black car or black shoes. Black can be a property yes! but it can also be a thing in and of itself.

Remember modal theory? Let me hint at it. Here it has become relevant but its proper introduction is still further ahead. How do we define an object? and how does it come to possess attributes? What is sky? is it the clouds, the air? The sum of its parts? Perhaps. Let's look at "black" it seems to belong to some kind of category? Yes? *It is a color after all* but if it's a color *Then what is a color?*

Such interesting questions oh such interesting questions. Just begging for intellectual attention :sigh: but I'm getting way ahead of myself. Let's pause for a moment, let me sip my entropying coffee.

Let's return to the familiar world of languages and symbols and introduce something foreign and scary, logical operators!! 

**[(R ⊃ T) v (S ⊃ U)] • [(W ≡ X) v (Y ≡ Z)]**

Logicians and mathematicians use these sorts of languages. Scary isn't it? Looking at complex symbols and notations that are apparently meaningful but only to the initiated. It is reminiscent of a regular expression. This a symbolic expression of a premise. Albeit more complex than `The sky is black` but it's still the same fundamentally. Here we introduce something called a **compound statement**. You can think of it as a bunch of functions communication with each other(notice the parallel with fp? ). Let's break down the cryptic and make it bare.

The ~ means negation similar to the programming equivalent of `not` or `!`
The • means conjunction it is basically `and` or `&&`
The v is called a wedge it's means disjunction aka `or` or `||`
The ⊃ is a horseshoe lol cute isn't it? it means implication in programming speak it's  `if(true) do: ...`
Lastly the ≡ is a triple bar unceremoniously. You must know this from mathematics? yes it's equivalence. Verbosely called "if and only if" In programming lingo `===` or any operation that performs deep equality of type and value. The letters are expressions.

Can you notice something wonderful?

It maps almost identically `1:1` to a programming language that is turing complete. It is just one kind of a formal language expression, like `NaCl` or dy/dx these languages aren't like the natural language. They've done away with so much of it with their perfect rules that make them *easier* to reason about and as always what happens when I/O comes into play? What happens when we need to create useful ideas with this tiny vocabulary of notations and make ACTUALLY useful software that expresses ideas? That is what we are, the human component. The interface between not man, but ideas and computers.

What happens when the boundary of a program extends you? It gets messy. Problems. Problems and more problems. Programs create safeguards to protect you `try except catch rescue` and what not, this is where functional programming shines. It reduces complexity by offering a stream of ideas. Returning thought not to it's messy philosophical origin of a universal object but the even more odd idea of a deterministic mechanical process. :)