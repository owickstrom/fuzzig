const std = @import("std");

const arb = @import("./arb.zig");
const Arbs = arb.Arbs;

const test_data = @import("./test_data.zig");
const TestData = test_data.TestData;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const test_allocator = gpa.allocator();

test "int" {
    const entropy = try test_data.random_bytes(test_allocator, 1024, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    const n = try Arbs.int(u32).draw(td, test_allocator);
    try std.testing.expectEqual(3743615817, n);
}

test "bounded_int" {
    const entropy = try test_data.random_bytes(test_allocator, 1024, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    for (0..100) |_| {
        const n = try Arbs.bounded_int(u32, 0, 10).draw(td, test_allocator);
        try std.testing.expect(n <= 10);
    }
}

test "slice" {
    // Number of ints we want to draw.
    const size = 10000;

    // Make sure there's enough entropy.
    const entropy = try test_data.random_bytes(test_allocator, @sizeOf(u32) * size, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    const ns = try Arbs.slice(u32, Arbs.bounded_int(u32, 0, 10), 0, size).draw(td, test_allocator);

    // We expect the `size` to be respected as we have enough entropy.
    try std.testing.expectEqual(size, ns.len);
    for (ns) |n| {
        try std.testing.expect(n <= 10);
    }
}

test "single weighted" {
    const entropy = try test_data.random_bytes(test_allocator, 1024, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    const n = try Arbs.frequencies(u32, &.{
        .{ 1, Arbs.bounded_int(u32, 10, 20) },
    }).draw(td, test_allocator);
    try std.testing.expectEqual(13, n);
}

test "multiple weighted" {
    const entropy = try test_data.random_bytes(test_allocator, 1024, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    const n = try Arbs.frequencies(u32, &.{
        .{ 1, Arbs.bounded_int(u32, 0, 10) },
        .{ 2, Arbs.bounded_int(u32, 10, 20) },
    }).draw(td, test_allocator);
    try std.testing.expectEqual(13, n);
}

test "constant" {
    var td = try TestData.init(test_allocator, &.{});
    defer td.deinit(test_allocator);

    const n = try Arbs.constant(u32, 10).draw(td, test_allocator);
    try std.testing.expectEqual(10, n);
}

const Color = enum { Red, Green, Blue };

test "enum_value" {
    const entropy = try test_data.random_bytes(test_allocator, 1024, 0);
    defer test_allocator.free(entropy);

    var td = try TestData.init(test_allocator, entropy);
    defer td.deinit(test_allocator);

    const color = try Arbs.enum_value(Color).draw(td, test_allocator);
    try std.testing.expectEqual(.Blue, color);
}
