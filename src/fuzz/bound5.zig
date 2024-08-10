const std = @import("std");

const fuzzig = @import("fuzzig");
const cli = @import("./cli.zig");
const arb = fuzzig.arb;
const TestData = fuzzig.TestData;

pub fn main() !void {
    try cli.fuzzer_main(fuzzig.examples.bound5);
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
