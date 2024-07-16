const std = @import("std");
const assert = std.debug.assert;

const TestData = @import("./test_data.zig").TestData;

const arb = @import("./arb.zig");
const Arb = arb.Arb;

const prop_test = @import("./prop.zig").prop_test;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const test_allocator = gpa.allocator();

const Example1Value = enum {
    V1,
    V2,
    V3,
    V4,
    V5,
};

fn prop_example1(values: []Example1Value) !void {
    for (values) |value| {
        try std.testing.expect(value != .V5);
    }
}

test "prop_test_example1" {
    try prop_test([]Example1Value, test_allocator, .{}, arb.slice(Example1Value, arb.enum_value(Example1Value), 0, 10), prop_example1);
}

fn prop_example2(values: []u32) !void {
    var count: u32 = 0;
    for (values) |value| {
        if (value < 10) {
            count += 1;
        }
    }
    try std.testing.expect(count <= values.len / 10);
}

test "prop_test_example2" {
    try prop_test([]u32, test_allocator, .{ .max_shrinks = 10000 }, arb.slice(u32, arb.bounded_int(u32, 0, 100), 1, 10), prop_example2);
}

pub fn Tree(T: type) type {
    return struct {
        label: T,
        left: ?*Tree(T) = null,
        right: ?*Tree(T) = null,
    };
}

fn arb_tree(data: *TestData, allocator: std.mem.Allocator) !*Tree(u32) {
    const numbers = arb.bounded_int(u32, 0, 10);
    var roots = std.fifo.LinearFifo(*Tree(u32), .Dynamic).init(allocator);
    var labels = std.fifo.LinearFifo(u32, .Dynamic).init(allocator);

    // Draw labels until out of entropy or configured size.
    // TODO: parameterize size somehow
    for (0..100) |_| {
        const label = numbers.draw(data, allocator) catch break;
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
fn prop_example3(tree: *Tree(u32)) !void {
    var seen = std.hash_map.AutoHashMap(u32, void).init(test_allocator);
    defer seen.deinit();

    var pending = std.fifo.LinearFifo(*Tree(u32), .Dynamic).init(test_allocator);
    defer pending.deinit();

    try pending.writeItem(@constCast(tree));

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

test "prop_test_example3" {
    try prop_test(*Tree(u32), test_allocator, .{ .max_shrinks = 10000 }, arb.from_fn(*Tree(u32), arb_tree), prop_example3);
}
