---
title: "It's legos all the way down"
date: 2023-01-25T22:42:06+01:00
draft: true
---

Often as folks who create useful software things we tend to think of ourselves as people who write software for the mythical "user". A "user" clicks a button and
something magical happens. This is commonly reffered to as an [abstraction](https://en.wikipedia.org/wiki/Abstraction_(computer_science)).
Abstractions are all around us in software and clever programmers create good abstractions for other programmers to save them valuable time and or other resources.

A really common example of this is an [Application Programming Interface](https://en.wikipedia.org/wiki/API) which allows two "applications" to talk to each other over
some transport. Like an API, there are other interesting kinds of abstractions -- let's talk about the one between the language creator and language user by _inventing
syntax_!

We'll be stepping through how to create a [dynamic array](https://en.wikipedia.org/wiki/Dynamic_array) constructor.

Before we begin, a caveat. Although this technique applies broadly to most modern languages, it is ergonomic to explore explicity with a language that has at least made some kind of syntactic/library provision, I'll try to primarily include alternate examples with go's [reflection](https://go.dev/blog/laws-of-reflection) and rust's [macro system](https://doc.rust-lang.org/book/ch19-06-macros.html) while providing nods to Cpython[[1]](#references) and Ruby MRI[[2]](#references) but not javascript [[3]](#references))

### AST what?

Abstract Syntax Tree. Okay but what is it? As this is intended to be written in a more hands-on style, at the risk
of oversimplification, think of an AST as a way to meaningfully represent the textual source of a program that sometimes allows you to do something resembling [string interpolation](https://en.wikipedia.org/wiki/String_interpolation) operations on your program's text source. Consider for example the humble `eval()` function:

javascript:

```javascript
console.log(eval('2 + 2'));
```

python:

```python3
print(eval('2 + 2'))
```

That's kind of neat isn't it? But what's going on here? how do we go from a `string` to a computation?

For the short story continue on! However if this question seems interesting check out [crafting interpreters](https://craftinginterpreters.com/).

### Building a (Dynamic) Array "constructor" in Elixir

First, some background. Elixir is a (mostly) functional language with (mostly) immutable datastructures, it doesn't encourage the use of
or provide a dynamic array out of the box like most functional languages, as the implementation of one
requires random access read/write via internal mutable state.

If you _really_ need one though, you can reach into the [erlang stdlib](https://www.erlang.org/doc/man/array.html).

For this we're going to piggyback off the rust standard library's [Vector](https://doc.rust-lang.org/std/vec/struct.Vec.html) and
creating a [foreign function interface](https://en.wikipedia.org/wiki/Foreign_function_interface) in elixir by re-creating rust's `vec!` macro api
eventually supporting either the erlang or rust version as a backend.

As we'll see the "backend" implementation of the data structure is not important, what we're focused on is providing an easy to use syntactic abstraction
of a common datastructure.

Here's a simplified version pull straight from [the rust book](https://doc.rust-lang.org/book/ch19-06-macros.html) of `vec!`:

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

Woaw, what's going on here?

_insert pattern matching and pre-compilation steps blah blah_

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

## References

[1] Python3's excellent `ast` library: <https://docs.python.org/3/library/ast.html>

[2] RubyVM::AST : <https://ruby-doc.org/core-trunk/RubyVM/AST.html>

[3] (footnote) I don't touch on Javascript(ECMAScript) as the language itself doesn't provide (afaik) useful apis to introspect and modify it's compile time state at runtime,
added to that is the ballooned complexity of _which_ version of the AST, what about typescript? which engine? you get unwanted complexity that is out of scope.

- <https://nodejs.dev/en/learn/the-v8-javascript-engine/>
- <https://basarat.gitbook.io/typescript/overview/ast>

[4] Go's AST : <https://pkg.go.dev/go/ast>

[5] Elixir's AST: <https://github.com/elixir-lang/elixir/blob/d8f1a5d6b653c14ae44c6eacdbc8e9df7006d284/lib/elixir/pages/syntax-reference.md#the-elixir-ast>
