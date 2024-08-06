const std = @import("std");

const arb = @import("./arb.zig");

const test_data = @import("./test_data.zig");
const TestData = test_data.TestData;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const test_allocator = gpa.allocator();

test "int" {
    const entropy = try test_data.random_bytes(test_allocator, 1024, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    const n = try arb.int(u32, td);
    try std.testing.expectEqual(3743615817, n);
}

test "bounded_int" {
    const entropy = try test_data.random_bytes(test_allocator, 1024, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    for (0..100) |_| {
        const n = try arb.bounded_int(u32, 0, 10, td);
        try std.testing.expect(n <= 10);
    }
}

test "array of bounded_int" {
    // Number of ints we want to draw.
    const size = 10000;

    // Make sure there's enough entropy.
    const entropy = try test_data.random_bytes(test_allocator, @sizeOf(u32) * size, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    var result: [size]u32 = undefined;
    for (0..size) |i| {
        result[i] = try arb.bounded_int(u32, 0, 10, td);
    }

    for (result) |n| {
        try std.testing.expect(n <= 10);
    }
}

test "single weighted" {
    const entropy = try test_data.random_bytes(test_allocator, 1024, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    const tag = try arb.weighted(enum { foo }, .{ .foo = 1 }, td);
    try std.testing.expectEqual(.foo, tag);
}

test "multiple weighted" {
    const entropy = try test_data.random_bytes(test_allocator, 1024, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    const x = try arb.weighted(enum { foo, bar }, .{
        .foo = 1,
        .bar = 2,
    }, td);
    try std.testing.expect(x == .foo or x == .bar);
}

test "many weighted" {
    // run with many seeds
    for (0..1000) |i| {
        const entropy = try test_data.random_bytes(test_allocator, 1024, i);
        defer test_allocator.free(entropy);

        var td = try TestData.init(test_allocator, entropy);
        defer td.deinit(test_allocator);

        const x = try arb.weighted(enum { foo }, .{
            .foo = 100,
        }, td);
        try std.testing.expect(x == .foo);
    }
}

const Color = enum { Red, Green, Blue };

test "enum_value" {
    const entropy = try test_data.random_bytes(test_allocator, 1024, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    const color = try arb.enum_value(Color, td);
    try std.testing.expectEqual(.Blue, color);
}
