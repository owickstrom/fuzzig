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

const Graph = struct {
    len: u64,
    edges: []std.ArrayList(Node),

    const Node = u64;
    const Edge = std.meta.Tuple(&.{ Node, Node });
    const Distance = u64;

    const Self = @This();

    fn init(allocator: std.mem.Allocator, edges: []const Edge) !Self {
        var max_node: u64 = 0;
        for (edges) |e| {
            max_node = @max(max_node, @max(e[0], e[1]));
        }
        const len = max_node + 1;
        var outbound = try allocator.alloc(std.ArrayList(Node), len);

        for (0..len) |n| {
            outbound[n] = std.ArrayList(Node).init(allocator);
        }

        for (edges) |e| {
            try outbound[e[0]].append(e[1]);
        }

        return .{ .len = len, .edges = outbound };
    }

    fn deinit(self: Self, _: std.mem.Allocator) void {
        for (self.edges) |e| {
            e.deinit();
        }
    }

    fn shortest_path(self: Self, allocator: std.mem.Allocator, source: Node) ![]?Distance {
        var unvisited = try std.bit_set.DynamicBitSetUnmanaged.initFull(allocator, self.len);
        defer unvisited.deinit(allocator);

        const distance_from_start = try allocator.alloc(?u64, self.len);
        for (0..self.len) |n| {
            distance_from_start[n] = null;
        }
        distance_from_start[source] = 0;

        while (unvisited.count() > 0) {
            // Select the current node to be the one with the smallest distance
            const Current = struct { node: Node, distance: Distance };
            var current: ?Current = null;
            var candidates = unvisited.iterator(.{});
            while (candidates.next()) |n| {
                if (distance_from_start[n]) |d| {
                    if (current) |c| {
                        if (d < c.distance) {
                            current = .{ .node = n, .distance = d };
                        }
                    } else {
                        current = .{ .node = n, .distance = d };
                    }
                }
            }

            if (current) |c| {
                // For the current node, consider all of its unvisited neighbors and update their
                // distances through the current node.
                for (self.edges[c.node].items) |neighbor| {
                    const old_distance = distance_from_start[neighbor];
                    const new_distance = c.distance + 1;
                    if (old_distance == null or new_distance < old_distance.?) {
                        distance_from_start[neighbor] = new_distance;
                    }
                }

                unvisited.setValue(c.node, false);
            } else {
                // The unvisited set contains only nodes with infinite distance (which are unreachable)
                break;
            }
        }

        return distance_from_start;
    }
};

test "graph shortest paths" {
    const edges = [_]Graph.Edge{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 0, 2 }, .{ 4, 5 }, .{ 3, 6 } };
    const g = try Graph.init(test_allocator, edges[0..]);
    defer g.deinit(test_allocator);

    const distances = try g.shortest_path(test_allocator, 0);
    defer test_allocator.free(distances);

    try std.testing.expectEqualSlices(?Graph.Node, distances, &.{ 0, 1, 1, 2, null, null, 3 });
}

test "graph shortest path is less than half" {
    for (0..1000) |seed| {
        const entropy = try test_data.random_bytes(test_allocator, 1024 * 1024, seed);
        defer test_allocator.free(entropy);

        var td = try TestData.init(test_allocator, entropy);
        defer td.deinit(test_allocator);

        const node_count = 42;
        var edges = try test_allocator.alloc(Graph.Edge, try arb.bounded_int(usize, 0, node_count * 4, td));
        for (0..edges.len) |i| {
            edges[i] = .{
                try arb.bounded_int(Graph.Node, 0, node_count, td),
                try arb.bounded_int(Graph.Node, 0, node_count, td),
            };
        }
        const g = try Graph.init(test_allocator, edges);
        defer g.deinit(test_allocator);

        const distances = try g.shortest_path(test_allocator, 0);
        defer test_allocator.free(distances);

        // std.debug.print("{any}\n", .{distances});

        for (distances) |distance| {
            if (distance != null and distance.? > @divFloor(node_count, 2)) {
                std.debug.print("{any}\n", .{edges});
                std.debug.print("{any}\n", .{distances});
                try std.testing.expect(false);
            }
        }
    }
}
