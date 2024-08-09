const std = @import("std");
const fuzzig = @import("fuzzig");
const TestData = fuzzig.TestData;

pub fn fuzzer_main(fuzzer: fn (std.mem.Allocator, *TestData) anyerror!void) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const stdin = std.io.getStdIn();
    const entropy = stdin.reader().any();
    defer stdin.close();

    var td = try fuzzig.test_data.from_reader(allocator, entropy);
    defer td.deinit(allocator);

    try fuzzer(allocator, td);
}
