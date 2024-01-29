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

- looping syntax...is very weird:

```zig
    for (array | slice) |value| {
        // use value do thing
    }
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

### First Impressions

```zig
const std = @import("std");
/////////////////////
// THROWAWAY NOTES //
/////////////////////

// struct with methods defined on `*Self` and associated by type
const Vector = struct {
    x: f64,
    y: f64,
    z: f64 = 69.420,

    fn print(self: *Vector) void {
        std.debug.print("{}", .{self});
    }

    fn magnitude(self: *Vector) f64 {
        var change = ((self.x * self.x) + (self.y * self.y) + (self.z * self.z));

        return std.math.pow(f64, change, 0.5);
    }

    fn sum(a: Vector, b: Vector) Vector {
        return Vector{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    fn iam(_: *Vector) Axiom {
        const rand = std.crypto.random;
        var axiom: i8 = rand.intRangeAtMost(i8, 1, 4);

        return @intToEnum(Axiom, axiom);
    }
};

// enums
const Axiom = enum { Associative, Commutative, Identity, Inverse };
const Errors = error{EigenVector};

pub fn main() void {
    // const var - var mut
    const thing: i32 = 5;
    var ichange: u32 = 50000;
    // do not shadow: var ichange: u32 = 8;

    _ = ichange;

    // explicit cast to type with @as
    const inferred_const = @as(i32, thing);
    _ = inferred_const;

    // fixed size array into slice
    var a = [5]u8{ 1, 2, 3, 4, 5 };
    // array slice
    var b = &[6]u8{ 'w', 'o', 'r', 'l', 'd', '\n' };
    var c: []u8 = a[0..3];
    _ = c;

    std.debug.print("{*}", .{b});

    // bad do not implicity initialise/alloc
    //var point = Vector{ 0.1, 0.2 };
    // this is okay though!
    var point = Vector{ .x = 0.1, .y = 0.2 };
    var point_two = Vector{ .x = 0.2, .y = 0.3 };

    std.debug.print("{}\n", .{point});
    std.debug.print("{}\n", .{point_two});
    std.debug.print("{}\n", .{point.magnitude()});
    std.debug.print("{}\n", .{Vector.sum(point, point_two)});
    std.debug.print("{}\n", .{point.iam()});
    std.debug.print("{}\n", .{isZero(5)});
    std.debug.print("{}\n", .{fitMePlease(50)});
    std.debug.print("{}\n", .{fitMePlease(512)});
    many();

    if (eigenVector(false)) |value| {
        std.debug.print("{}\n", .{value});
    } else |err| {
        std.debug.print("{}\n", .{err});
    }
}

fn isZero(x: i32) bool {
    if (x == 0) {
        return true;
    } else {
        return false;
    }
}

fn fitMePlease(x: f32) bool {
    var divisible: u32 = @floatToInt(u32, @divFloor(x, 2));

    return switch (divisible) {
        2 => true,
        4 => true,
        8 => true,
        16 => true,
        32 => true,
        64 => true,
        128 => true,
        256 => true,
        // for exhaustive known invariants being ignored
        // _ => true
        else => false,
    };
}

fn many() void {
    var array = [_]i32{ 1, 2, 3 };

    for (array) |value| {
        std.debug.print("loop: {}\n", .{value});
    }
}

fn eigenVector(todo: bool) !i32 {
    if (todo == true) {
        return Errors.EigenVector;
    } else {
        return 69;
    }
}
```