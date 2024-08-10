const std = @import("std");
const assert = std.debug.assert;

const TestData = @import("./test_data.zig").TestData;

const arb = @import("./arb.zig");
const Arb = arb.Arb;

const prop = @import("./prop.zig");

const bound5 = @import("./examples/bound5.zig").bound5;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const test_allocator = gpa.allocator();

const Example1Value = enum {
    V1,
    V2,
    V3,
    V4,
    V5,
};

fn prop_example1(data: *TestData) !void {
    for (0..5) |_| {
        const value = try arb.enum_value(Example1Value, data);
        try std.testing.expect(value != .V5);
    }
}

test "prop_check_example1" {
    const result = prop.check(test_allocator, .{}, prop_example1);
    try std.testing.expectError(error.TestUnexpectedResult, result);
}

fn prop_example2(data: *TestData) !void {
    var count: u32 = 0;
    for (0..100) |_| {
        const value = try arb.bounded_int(u32, 0, 100, data);
        if (value < 10) {
            count += 1;
        }
    }
    try std.testing.expect(count <= 10);
}

test "prop_check_example2" {
    const result = prop.check(test_allocator, .{ .max_shrinks = 10000 }, prop_example2);
    try std.testing.expectError(error.TestUnexpectedResult, result);
}

pub fn Tree(T: type) type {
    return struct {
        label: T,
        left: ?*Tree(T) = null,
        right: ?*Tree(T) = null,
    };
}

fn arb_tree(data: *TestData, allocator: std.mem.Allocator) !*const Tree(u32) {
    var roots = std.fifo.LinearFifo(*Tree(u32), .Dynamic).init(allocator);
    var labels = std.fifo.LinearFifo(u32, .Dynamic).init(allocator);

    // Draw labels until out of entropy or configured size.
    // TODO: parameterize size somehow
    for (0..100) |_| {
        const label = arb.bounded_int(u32, 0, 10, data) catch break;
        try labels.writeItem(label);
    }

    var root = try allocator.create(Tree(u32));
    root.label = labels.readItem().?;
    try roots.writeItem(root);

    // Divide generated labels into a tree.
    while (roots.readableLength() > 0) {
        var tree = roots.readItem() orelse break;
        tree.left = blk: {
            const label_left = labels.readItem() orelse break :blk null;
            const left = try allocator.create(Tree(u32));
            left.label = label_left;
            try roots.writeItem(left);
            break :blk left;
        };
        tree.right = blk: {
            const label_right = labels.readItem() orelse break :blk null;
            const right = try allocator.create(Tree(u32));
            right.label = label_right;
            try roots.writeItem(right);
            break :blk right;
        };
    }

    return root;
}

// Tries to find a tree with duplicate labels
fn prop_example3(data: *TestData) !void {
    var seen = std.hash_map.AutoHashMap(u32, void).init(test_allocator);
    defer seen.deinit();

    var pending = std.fifo.LinearFifo(*const Tree(u32), .Dynamic).init(test_allocator);
    defer pending.deinit();

    const tree = try arb_tree(data, test_allocator);

    try pending.writeItem(tree);

    while (pending.readableLength() > 0) {
        const tree_new = pending.readItem() orelse break;
        try std.testing.expect(seen.get(tree_new.label) == null);
        try seen.put(tree_new.label, {});

        if (tree_new.left) |left| {
            try pending.writeItem(left);
        }
        if (tree_new.right) |right| {
            try pending.writeItem(right);
        }
    }
}

test "prop_check_example3" {
    const result = prop.check(test_allocator, .{ .max_shrinks = 10000 }, prop_example3);
    try std.testing.expectError(error.TestUnexpectedResult, result);
}

fn prop_bound5(td: *TestData) !void {
    try bound5(test_allocator, td);
}

test "prop_check_bound5" {
    const result = prop.check(test_allocator, .{ .runs = 1000, .max_shrinks = 50000 }, prop_bound5);
    try std.testing.expectError(error.TestUnexpectedResult, result);
}
