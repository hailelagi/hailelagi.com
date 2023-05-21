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
