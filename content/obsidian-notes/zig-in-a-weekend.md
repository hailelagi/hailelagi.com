---
title: "Zig In a Weekend"
date: 2023-05-21T07:47:25+01:00
obsidian-import: true
draft: true
do-not-render: true
---

## Quick Start

- <https://ziglearn.org/>
- <https://gist.github.com/ityonemo/769532c2017ed9143f3571e5ac104e50>

## Kata/Practice

- ziglings

### WTFs

- Scoped Resource allocation
- opt-in compile time evaluation via `comptime`
- Zig is unstable. `brew install zig` gives `0.10` which is old -- Building from source sucks but is _required_ to experiment with the interesting things folks are making. ~1 hour later after building and verify public keys:

```zsh
0.11.0-dev.3222+7077e90b3
```

- this syntax is weird `var variable: MyStruct = .{ values, .key=value };`
- resouce density is sparse? weird mix of unexpected prerequisites: errors are not obvious.
- printing comptime values... is hard??
- implicit allocation is bad?

```zsh
# implicit allocations are disallowed by the compiler
main.zig:18:32: error: type 'main.Vector' does not support array initialization syntax
```

## Hello -- `hello world`

```zig
const std = @import("std");

pub fn main() void {
    std.debug.print("Hello, {s}!\n", .{"World"});
    std.debug.print("Hello cruel world\n", .{});
}

```

```zig
// minimum viable zig program
fn pub main() void {}
```

- printing/logging

```zig
const std = @import("std");
var thing: type = value;

pub fn main() void {
    // std.log
    std.debug.print(thing, .{});
}
```
