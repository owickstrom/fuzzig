const std = @import("std");

const fuzzig = @import("fuzzig");
const cli = @import("./cli.zig");
const arb = fuzzig.arb;
const TestData = fuzzig.TestData;

const Input = [5]std.ArrayList(i16);

fn bound5(allocator: std.mem.Allocator, td: *TestData) !void {
    var input: Input = undefined;
    for (0..5) |i| {
        var numbers = std.ArrayList(i16).init(allocator);

        for (0..1) |_| {
            const n = arb.int(i16, td) catch break;
            try numbers.append(n);
        }

        input[i] = numbers;
    }

    defer for (input) |numbers| {
        std.debug.print("{any}\n", .{numbers.items});
        numbers.deinit();
    };

    try property(input);
}

fn property(input: Input) !void {
    if (precondition(input)) {
        try std.testing.expect(postcondition(input));
    }
}

fn precondition(input: Input) bool {
    for (input) |list| {
        var sum: i16 = 0;
        for (list.items) |n| {
            sum += n;
        }
        if (sum >= 256) return false;
    }
    return true;
}

fn postcondition(input: Input) bool {
    var sum: i16 = 0;
    for (input) |list| {
        for (list.items) |n| {
            sum += n;
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
