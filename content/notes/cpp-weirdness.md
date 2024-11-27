---
title: "Cpp Weirdness"
date: 2024-10-23T13:09:40+01:00
draft: true
---

"fun" c++ "facts":
- multiple inheritance
- https://en.wikipedia.org/wiki/Copy_elision
- https://eli.thegreenplace.net/2012/06/28/the-type-variable-name-ambiguity-in-c
- https://en.wikipedia.org/wiki/Most_vexing_parse
- the thin-air problem: https://www.cl.cam.ac.uk/~pes20/cpp/notes42.html
- Curiously recurring templates: https://en.wikipedia.org/wiki/Curiously_recurring_template_pattern

things I don't like:
~~syntax ambiguity~~ not that bad
classes gymnastics: still prefer traits + types
pointer arithmetic
~~cmake, build tooling learning curve~~ zig


a really good/simple description of the essence of a `vtable`, no need to know about coherence/orphaning!

> The usual implementation technique is for the compiler to convert the name of a virtual function into an index into a table of pointers to functions. That table is usually called the virtual function table or simply the vtbl.

> The throw transfers control to a handler for exceptions of type out_of_range in some function that directly or indirectly called Vector::operator[](). To do that, the implementation will unwind the function call stack as needed to get back to the context of that caller. That is, the exception handling mechanism will exit scopes and functions as needed to get back to a caller that has expressed interest in handling that kind of exception, invoking destructors (§4.2.2) along the way as needed.
exceptions unwind the callstack + call destructors = ez memory cleanup (assuming your destructors are correct?) 

equivalent of `Drop` during unwind at `panic`, however possible to dangle with bad `Drop` impls, so same, same sort of?
still yet to find a good answer in rust.
