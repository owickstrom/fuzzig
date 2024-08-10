const std = @import("std");

const fuzzig = @import("fuzzig");
const cli = @import("./cli.zig");
const arb = fuzzig.arb;
const TestData = fuzzig.TestData;

const Input = [5][]const i16;

fn bound5(allocator: std.mem.Allocator, td: *TestData) !void {
    var input: Input = undefined;
    for (0..5) |i| {
        var numbers = try allocator.alloc(i16, 1);

        for (0..numbers.len) |n| {
            numbers[n] = try arb.int(i16, td);
        }

        input[i] = numbers;
        std.debug.print("{any}\n", .{numbers});
    }

    defer for (input) |numbers| {
        allocator.free(numbers);
    };

    try property(input);
}

fn property(input: Input) !void {
    if (precondition(input)) {
        try std.testing.expect(postcondition(input));
    }
}

fn precondition(input: Input) bool {
    for (input) |numbers| {
        var sum: i16 = 0;
        for (numbers) |n| {
            sum +%= n;
        }
        std.debug.print("precondition sum {any} = {d}\n", .{ numbers, sum });
        if (sum >= 256) return false;
    }
    return true;
}

fn postcondition(input: Input) bool {
    var sum: i16 = 0;
    for (input) |numbers| {
        for (numbers) |n| {
            sum +%= n;
        }
    }
    std.debug.print("sum: {d}\n", .{sum});
    return sum < (256 * 5);
}

pub fn main() !void {
    try cli.fuzzer_main(bound5);
}

fn cMain() callconv(.C) void {
    main() catch unreachable;
}

comptime {
    @export(cMain, .{
        .name = "main",
        .linkage = .strong,
    });
}
