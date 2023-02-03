---
title: "It's legos all the way down"
date: 2023-01-25T22:42:06+01:00
draft: true
---

Often as folks who create useful software things we tend to think of ourselves as people who write software for "users". A "user" clicks a button and
something magical happens. This is what is commonly reffered to as an [abstraction](https://en.wikipedia.org/wiki/Abstraction_(computer_science)).
Abstractions are all around us in software and clever programmers create abstractions for other programmers to save them valuable time and or other resources.

A really common example of this is an [Application Programming Interface](https://en.wikipedia.org/wiki/API) which allows two "applications" to talk to each other over
some transport. Like an API, there are other interesting kinds of abstractions -- let's talk about the one between the language creator and language user by creating an
[array](https://en.wikipedia.org/wiki/Array_(data_structure)) in elixir.

Before we begin! A caveat. Although the concepts here apply broadly to most modern languages, it is most convenient to explore these concepts explicity with a language that has at least
made some kind of provision for them, I'll try to primarily include alternate examples with go's [reflection](https://go.dev/blog/laws-of-reflection) and rust's macros while providing references
for exploring the AST for Cpython and MRIRuby (javascript sadly not included![1])

### Building a (Dynamic) Array "constructor" in Elixir

First, some background. Elixir is a (mostly) functional language with (mostly) immutable datastructures, it doesn't provide a dynamic array out of the box, as the implementation of one
requires internally mutable state. If you _really_ need one though, you can reach into the [erlang stdlib](https://www.erlang.org/doc/man/array.html).

For this we're going to piggyback of the rust standard library's [Vector](https://doc.rust-lang.org/std/vec/struct.Vec.html) and 
creating a [foreign function interface](https://en.wikipedia.org/wiki/Foreign_function_interface) in elixir by re-creating rust's `vec!` macro api. 
Here's a simplified version pull straight from the rust book of what this looks like:

```rust
#[macro_export]
macro_rules! vec {
    ( $( $x:expr ),* ) => {
        {
            let mut temp_vec = Vec::new();
            $(
                temp_vec.push($x);
            )*
            temp_vec
        }
    };
}

```

In elixir we can begin like so:

```elixir
defmodule Vector do
  defmacro vec!(arguments, do: expression) do
    quote do
      Array.new(arguments)
    end
  end
end
```

### Foot notes

[1] I don't touch on Javascript(ECMAScript) as the language itself doesn't provide (afaik) useful apis to introspect it's compile time state at  runtime,
added to that is the balloned complexity of _which_ version of the AST, by which engine is produced and you get unwanted complexity that is out of scope.
(<https://nodejs.dev/en/learn/the-v8-javascript-engine/>)

[2] AST reference: https://github.com/elixir-lang/elixir/blob/d8f1a5d6b653c14ae44c6eacdbc8e9df7006d284/lib/elixir/pages/syntax-reference.md#the-elixir-ast
