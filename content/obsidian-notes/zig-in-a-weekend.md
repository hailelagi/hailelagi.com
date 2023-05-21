---
title: "Zig In a Weekend"
date: 2023-05-21T07:47:25+01:00
obsidian-import: true
draft: true
do-not-render: true
---

### WTFs

- Scoped Resource allocation
- opt-in compile time evaluation via `comptime`
- Zig is unstable. `brew install zig` gives `0.10` which is old -- Building from source sucks but is _required_ to experiment with the interesting things folks are making. ~1 hour later after building and verify public keys:

```zsh
0.11.0-dev.3222+7077e90b3
```

## Hello -- `hello world`

```zig
const std = @import("std");

pub fn main() void {
    std.debug.print("Hello, {s}!\n", .{"World"});
}

```
