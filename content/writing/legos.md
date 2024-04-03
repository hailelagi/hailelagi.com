---
title: "It's legos all the way down"
date: 2023-02-17T04:59:26+01:00
draft: false
---

### Introduction

Often as folks who create useful software things we tend to think of ourselves as people who write software for the mythical "user". A "user" clicks a button and
something magical happens. This is commonly reffered to as an [abstraction](https://en.wikipedia.org/wiki/Abstraction_(computer_science)).
Abstractions are all around us in software and clever programmers create good abstractions for other programmers often to manage complexity.

A really common example of this is an [Application Programming Interface](https://en.wikipedia.org/wiki/API) which allows two "applications" to share useful data with each other over some transport while being platform-agnostic as to how this data is used. Like an API, there are other interesting kinds of abstractions -- let's peel back the abstraction between the language creator and language user by _inventing syntax!_

This involves a subtle shift in the paradigm used to understand computation, at the _core_ is the idea of viewing **computation as data**. I would guess for most people,
the typical mental model when reading at first is mostly _procedural_, a top-down scan with familiarity of syntax and semantics, then another important shift occurs in
understanding runtime execution with the introduction of concurrency and parallelism, here we'll be peeling back at the layer between _compile time_ and _runtime_.

Compile time occurs when program text is being "parsed and transformed" into many forms all the way to bits and runtime
is when the program is actually executing ie "running", in this paradigm of viewing programs as textual input to other programs and to the program itself while running, is known as metaprogramming.

<!-- TODO: impl a callout partial dammn it -->
This distinction between what is "compile" and "runtime" is
 a useful mental model illustrated here for simplicity, odds
 are what's happening in your favorite language is probably 
 more interesting! [^1]

Before we begin, a caveat. Although this technique applies broadly to most modern languages -- implementations vary in feature parity, I'll try to primarily include alternate examples with go's [reflection](https://go.dev/blog/laws-of-reflection) and rust's [macro system](https://doc.rust-lang.org/book/ch19-06-macros.html) while providing nods to Cpython[^2], Ruby MRI [^3] and some javascript [^4] but not typescript [^5]

### Computation is data

 Consider for example the humble `eval()` function:

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
If you're interested in further details of what's happening here, checkout [crafting interpreters](https://craftinginterpreters.com/).

Since programming languages contain all sorts of elements like _expressions_ and _statements_, we need some
way to hold information about what the program or computation is trying to do, this internal representation is most commonly known as an Abstract Syntax Tree.

At the risk of oversimplification, think of an AST as a way to meaningfully represent the textual source of a program that sometimes allows you to do something resembling [string interpolation](https://en.wikipedia.org/wiki/String_interpolation) operations on your program's text source.

### Prelude, why meta?

To illustrate this concept, lets see how one might add syntax to create a [constructor](https://en.wikipedia.org/wiki/Constructor_(object-oriented_programming)) for a [dynamic array](https://en.wikipedia.org/wiki/Dynamic_array) in `elixir`.

First, some background. Elixir is a (mostly) functional language with (mostly) immutable datastructures, it doesn't encourage the use of
or provide a dynamic array out of the box like most functional languages, as the implementation of one
requires random access read/write via mutable state. Nor does it have "constructors", a typical pattern is creating structured data returned from
a function and ["piping"](https://elixirschool.com/en/lessons/basics/pipe_operator) it through several other functions:

```elixir
defmodule MyApp.Array do
  alias MyApp.Array

  defstruct field: nil

  def new(options \\ []) do
    %Array{field: options}
  end
end

iex(1)> MyApp.Array.new() |> do_stuff() |> do_other_stuff()
```

For this example, we're going to piggyback off the rust standard library's [Vector](https://doc.rust-lang.org/std/vec/struct.Vec.html) by
creating a [foreign function interface](https://en.wikipedia.org/wiki/Foreign_function_interface) in elixir and alternatively a data structure implemented in the [erlang stdlib](https://www.erlang.org/doc/man/array.html) in order to re-create something like `vec!`

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

In elixir, we can write something similar, the pattern match is a three-element style tuple[^7]:

`{node, execution_context or meta_data, arguments}`

Go and ruby share some superficial similarities as their metaprogramming api doesn't give you direct access to the AST [^6]. In ruby libraries like `RSpec`,`rails` router and `erb` html templates often use metaprogramming techniques via "monkey patching" -- modifying at _runtime_ various
properties of an object[^8] and since in ruby's _extremely dynamically typed_[^9] interpreted world there is no notion of "compile time expansion" instead you have powerful introspection and malleability at runtime giving rise to patterns like `hooks`[^10] to alter nearly almost anything about the language via object properties, syntax or not.

Take this small excerpt[^10] from [rspec-core](https://github.com/rspec/rspec-core) of the `describe` public api:

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

There's alot happening but the important thing to note is `RSpec::Core::ExampleGroup` is an object that is being modified at the test-runner's runtime which specifies the linguistic structure of the _domain's specific language_[^11] of what `describe` means.

In go like ruby we have `reflection` that allows runtime introspection [^6], unlike ruby it is statically typed and compiled. Reflection gives a temporary "escape hatch" out of the rigid type system and allows modification based on dynamic `interfaces` the most idiomatic example of this I can find are the printing family[^12] functions like `fmt.Sprintf`.

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

Now, let's get hands on. Everything here lives in a mix project called [`ExVec`](https://github.com/hailelagi/ex_vec) and defining the macro's public api:

```elixir
defmodule ExVec do
  alias ExVec.{Array, Vector}

  defmacro __using__(implementation: impl) do
    quote do
      import unquote(__MODULE__)
      Module.put_attribute(__MODULE__, :implementation, unquote(impl))
    end
  end

  defmacro vec!([_h | _t] = args) do
    quote bind_quoted: [args: args] do
      dispatch_constructor(@implementation, args)
    end
  end

  defmacro vec!({:.., _, [first, last]}) do
    args = Range.new(first, last) |> Enum.to_list()

    quote bind_quoted: [args: args] do
      dispatch_constructor(@implementation, args)
    end
  end

  def dispatch_constructor(impl, args) do
    case impl do
      :rust -> Vector.new(args)
      :erlang -> Array.new(args)
      _ -> raise "invalid constructor type, did you mean :rust?"
    end
  end
end
```

The `ex_vec` library has two backends `ExVec.Array` which is a thin wrapper around [`:array`](https://www.erlang.org/doc/man/array.html) and `ExVec.Vector` which is a NIF wrapper that leverages rustler's `Encoder` and `Decoder` to encode an elixir `List` as a `Vec` then implementing interfaces for what an array might look like in elixir by defining:

1. The `Access` behaviour
2. A protocol implementation of `Enumerable`

By implementing these specifications we can safely use things from stdlib like `Enum` and even `Stream` and just like that in any other elixir project
and letting the client choose the backend while keep the macro's syntax:

```elixir
defmodule MyApp.DoStuff do
  alias ExVec.Vector
  use ExVec, implementation: :rust

  def len do
    # serialised as a rust Vec<i32>
    vec!(1..4) |> Enum.count()
    vec!([1, 2, 3, 4]) |> Enum.count()

    # plain old linked-list
    [1, 2, 3, 4] |> Enum.count()
  end

  def random_access do
    # O(1) read
    my_array = vec!(0..10)
    my_array[5]

     # serialised random write access
    Vector.get_and_update(my_array, 0, fn n -> {n, 42} end)
  end
end

defmodule MyApp.DoOtherStuff do
  use ExVec, implementation: :erlang

  def len do
    # this is an erlang :array!
    vec!([1, 2, 3, 4]) |> Enum.count()
  end
end
```

unfortunately as of the time of this writing, `rustler` [does not support](https://github.com/rusterlium/rustler/issues/424) generic type intefaces so I
guess this is impossible?

```rust
#[derive(Debug, NifStruct)]
#[module = "ExVec.Vector"]
pub struct Vector<T> {
   fields: Vec<T>,
   size: isize
}
```

Therefore a serious limitation of this toy example is it only works for `i32` integers :) I also glossed over some behaviours and protocols with defaults.

 You can find the full source for this example [here](https://github.com/hailelagi/ex_vec), please let me know if you have a comment, found a bug or typo. Thanks for reading!

## References

[^1]: [Just in Time compilation](https://en.wikipedia.org/wiki/Just-in-time_compilation)

[^2]: [Python3's `ast` library](https://docs.python.org/3/library/ast.html)

[^3]: [RubyVM::AST module](https://ruby-doc.org/core-trunk/RubyVM/AST.html)

[^4]: [Reflection Javascript(since ECMAScript6)](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Reflect)

[^5]: [Basarat's Typescript AST Guide](https://basarat.gitbook.io/typescript/overview)

[^6]: [Go's AST package](https://pkg.go.dev/go/ast)

[^7]: [Elixir's AST doc](https://github.com/elixir-lang/elixir/blob/d8f1a5d6b653c14ae44c6eacdbc8e9df7006d284/lib/elixir/pages/syntax-reference.md#the-elixir-ast)

[^8]: [The one true (_useful_) object to rule them all](https://ruby-doc.org/3.2.1/Object.html)

[^9]: [Ruby Extensions](https://docs.ruby-lang.org/en/master/extension_rdoc.html#label-Basic+Knowledge)

[^10]: [Awesome example of the `hook pattern` into ruby's object lifecyle](https://github.com/rspec/rspec-core/blob/main/lib/rspec/core/hooks.rb)

[^11]: [RSpec public DSL module](https://github.com/rspec/rspec-core/blob/main/lib/rspec/core/dsl.rb)

[^12]: [doPrint source](https://cs.opensource.google/go/go/+/refs/tags/go1.20:src/fmt/print.go;drc=261fe25c83a94fc3defe064baed3944cd3d16959;l=1204)
