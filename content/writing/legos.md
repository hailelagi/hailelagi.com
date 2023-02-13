---
title: "It's legos all the way down"
date: 2023-01-25T22:42:06+01:00
draft: false
---

Often as folks who create useful software things we tend to think of ourselves as people who write software for the mythical "user". A "user" clicks a button and
something magical happens. This is commonly reffered to as an [abstraction](https://en.wikipedia.org/wiki/Abstraction_(computer_science)).
Abstractions are all around us in software and clever programmers create good abstractions for other programmers to save them valuable time and or other resources.

A really common example of this is an [Application Programming Interface](https://en.wikipedia.org/wiki/API) which allows two "applications" to talk to each other over
some transport. Like an API, there are other interesting kinds of abstractions -- let's talk about the one between the language creator and language user by _inventing
syntax!_

How? we'll define a [constructor](https://en.wikipedia.org/wiki/Constructor_(object-oriented_programming)) for a [dynamic array](https://en.wikipedia.org/wiki/Dynamic_array) in `elixir`.

This involves a subtle shift in the paradigm used to understand computation, at the core is the idea of viewing _computation_ as _data_. I would guess for most people,
the typical mental model when reading at first is mostly _procedural_, a top-down scan with familiarity of syntax and semantics, then another important shift occurs in
understanding runtime execution with the introduction of concurrency and parallelism, here we'll be peeling back at the layer between _compile time_ and _runtime_.

Before we begin, a caveat. Although metaprogramming applies broadly to most modern languages -- implementations vary in feature parity, I'll try to primarily include alternate examples with go's [reflection](https://go.dev/blog/laws-of-reflection) and rust's [macro system](https://doc.rust-lang.org/book/ch19-06-macros.html) while providing nods to Cpython[[1]](#references), Ruby MRI[[2]](#references) and some javascript [[3]](#references)) but not typescript[[4]](#references)

### AST what?

Abstract Syntax Tree. Okay but what is it? As this is intended to be written in a more hands-on style, at the risk
of oversimplification, think of an AST as a way to meaningfully represent the textual source of a program that sometimes allows you to do something resembling [string interpolation](https://en.wikipedia.org/wiki/String_interpolation) operations on your program's text source. Consider for example the humble `eval()` function:

```javascript
// javascript
console.log(eval('2 + 2'));
```

```python3
# python
print(eval('2 + 2'))
```

```ruby
# ruby
puts eval('2 + 2')
```

The computation `2 + 2` is represented as data, in this case a `string`. That's kind of neat isn't it? however we can take this much futher.
If you're interested in the details of what's happening here, checkout [crafting interpreters](https://craftinginterpreters.com/).

### Prelude, why meta?

First, some background. Elixir is a (mostly) functional language with (mostly) immutable datastructures, it doesn't encourage the use of
or provide a dynamic array out of the box like most functional languages, as the implementation of one
requires random access read/write via mutable state. Nor does it have "constructors", a typical pattern is creating an instance of data returned from
a function and ["piping"](https://elixirschool.com/en/lessons/basics/pipe_operator) it through several other functions:

```elixir
defmodule MyApp.Array do
  defstruct field: nil

  def new(options \\ []) do
    __MODULE__{field: options}
  end
end

iex(1)> MyApp.Array.new() |> do_stuff() |> do_other_stuff()
```

For this example, we're going to piggyback off the rust standard library's [Vector](https://doc.rust-lang.org/std/vec/struct.Vec.html) by
creating a [foreign function interface](https://en.wikipedia.org/wiki/Foreign_function_interface) in elixir and utilizing a data structure implemented in the [erlang stdlib](https://www.erlang.org/doc/man/array.html) in order to re-create something like `vec!`

As we'll see the "backend" implementation of the data structure is not important, the fact that it's in rust or erlang doesn't matter, what we're focused on is providing an easy to use syntactic abstraction
of a common datastructure.

Here's a simplified version pulled straight from [the rust book](https://doc.rust-lang.org/book/ch19-06-macros.html) of `vec!`:

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

Here we see a pattern match `( $( $x:expr ),* )` like our humble `eval('2 + 2')` instead of representing the computation as a string, it's a tree like data-structure
where we can assert at compile time, if some code looks like what we think it looks like, replace it with what's in the match arm,
a process known as `macro expansion`.

In elixir, we can write something similar, the pattern match is a three-element style tuple[[5]](#references):

`{node, execution_context or meta_data, arguments}`

Go and ruby share some superficial similarities as their metaprogramming api doesn't give you direct access to the AST, in ruby DSL's like `RSpec` and inside `rails` heavily use metaprogramming techniques via "monkey patching" -- modifying at _runtime_ various
properties of an object[[6]](#references) and since in ruby's _extremely dynamic_ and _untyped_[[7]](#references) world there is no notion of "compile time expansion" during execution but that gives you incredible introspection and malleability via `hooks`[[8]](#references) to alter nearly almost anything about the language, syntax or not.

Take this small excerpt[[9]](#references) from [rspec-core](https://github.com/rspec/rspec-core) of how `describe` is defined:

```ruby
# @private
def self.expose_example_group_alias(name)
  return if example_group_aliases.include?(name)

  example_group_aliases << name

  (class << RSpec; self; end).__send__(:define_method, name) do |*args, &example_group_block|
    group = RSpec::Core::ExampleGroup.__send__(name, *args, &example_group_block)
    RSpec.world.record(group)
    group
  end

  expose_example_group_alias_globally(name) if exposed_globally?
end
```

There's alot happening but the important thing to note is `RSpec::Core::ExampleGroup` is an object that "pun intended" is being modified at the test-runner's runtime which describes the linguistic structure of the dsl.

In go like ruby we have `reflection` that allows runtime introspection, unlike ruby it is statically typed and compiled. Reflection gives a temporary "escape hatch" out of the rigid
syntatical constructs and allows modification based on dynamic `interfaces`, the most idiomatic example of this are the printing family[[10]](#references) functions.

```go
func (p *pp) doPrint(a []any) {
 prevString := false
 for argNum, arg := range a {
  isString := arg != nil && reflect.TypeOf(arg).Kind() == reflect.String
  // Add a space between two non-string arguments.
  if argNum > 0 && !isString && !prevString {
   p.buf.writeByte(' ')
  }
  p.printArg(arg, 'v')
  prevString = isString
 }
}
```

### Building a (Dynamic) Array "constructor" in Elixir

Now we're finally ready! We're going to begin by starting a mix project called [`ExVec`](https://github.com/hailelagi/ex_vec) and defining a similiar api:

```elixir
defmodule ExVec do
  defmacro vec!(arguments, do: expression) do
    quote do
      ExVec.Vector.new(arguments)
    end
  end
end
```

The `ex_vec` library has two backends `ExVec.Array` which is a thin wrapper around `:array` and `ExVec.Vector` which is a NIF wrapper that
implements what an array might look like in elixir:

1. The `Access` behaviour
2. A protocol implementation of `Enumerable` and `Collectable`

By specifying these functions we can safely use things from stdlib like `Enum` and even `Stream` and just like that in any other elixir project
and letting the client choose the backend:

```
defmodule MyApp.DoStuff do
  use ExVec, implementation: :rust

  @test_data [1, 2, 3, 4, 5]

  def len do
    vec!(1, 2, 3, 4) |> Enum.count()
  end

  def map_by_2 do
    vec!(1, 2, 3, 4) |> Enum.map(fn n -> n * 2 end)
  end
end
```

Thanks for reading!

You can find the full source for this example [here](https://github.com/hailelagi/ex_vec)

## References

[1] Python3's excellent `ast` library: <https://docs.python.org/3/library/ast.html>

[2] RubyVM::AST : <https://ruby-doc.org/core-trunk/RubyVM/AST.html>

[3] Javascript(since ECMAScript6): <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Reflect>

[4] Typescript: <https://basarat.gitbook.io/typescript/overview>

[4] Go's AST : <https://pkg.go.dev/go/ast>

[5] Elixir's AST: <https://github.com/elixir-lang/elixir/blob/d8f1a5d6b653c14ae44c6eacdbc8e9df7006d284/lib/elixir/pages/syntax-reference.md#the-elixir-ast>

[6] The one true (_useful_) object to rule them all: <https://ruby-doc.org/3.2.1/Object.html>

[7] Ruby Extensions: <https://docs.ruby-lang.org/en/master/extension_rdoc.html#label-Basic+Knowledge>

[8] Awesome example of the `hook pattern` into ruby's object lifecyle: <https://github.com/rspec/rspec-core/blob/main/lib/rspec/core/hooks.rb>

[9] RSpec public DSL module: <https://github.com/rspec/rspec-core/blob/main/lib/rspec/core/dsl.rb>

[10] doPrint: <https://cs.opensource.google/go/go/+/refs/tags/go1.20:src/fmt/print.go;drc=261fe25c83a94fc3defe064baed3944cd3d16959;l=1204>
