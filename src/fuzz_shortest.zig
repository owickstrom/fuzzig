const std = @import("std");

const fuzzig = @import("fuzzig");
const fuzz = @import("./fuzz.zig");
const arb = fuzzig.arb;
const TestData = fuzzig.TestData;

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

    fn deinit(self: Self, allocator: std.mem.Allocator) void {
        for (self.edges) |e| {
            e.deinit();
        }
        allocator.free(self.edges);
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const edges = [_]Graph.Edge{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 0, 2 }, .{ 4, 5 }, .{ 3, 6 } };
    const g = try Graph.init(allocator, edges[0..]);
    defer g.deinit(allocator);

    const distances = try g.shortest_path(allocator, 0);
    defer allocator.free(distances);

    try std.testing.expectEqualSlices(?Graph.Node, distances, &.{ 0, 1, 1, 2, null, null, 3 });
}

fn edge(td: *TestData) !Graph.Edge {
    return .{
        try arb.bounded_int(Graph.Node, 0, 42, td),
        try arb.bounded_int(Graph.Node, 0, 42, td),
    };
}

fn graph_shortest_path_no_longer_than_half(allocator: std.mem.Allocator, td: *TestData) !void {
    var edges = std.ArrayList(Graph.Edge).init(allocator);
    defer edges.deinit();

    const nodes = try arb.bounded_int(u8, 0, 100, td);
    for (0..nodes) |_| {
        if (edge(td)) |e| {
            try edges.append(e);
        } else |_| {
            break;
        }
    }

    const g = try Graph.init(allocator, edges.items);
    defer g.deinit(allocator);

    const distances = try g.shortest_path(allocator, 0);
    defer allocator.free(distances);

    for (distances, 0..) |distance, i| {
        const threshold = @divFloor(g.len, 2);
        if (distance != null and g.len >= 42 and distance.? > threshold) {
            std.debug.print("distance ({d}) from start to node {d} was greater than {d}\n", .{ distance.?, i, threshold });
            std.debug.print("edges: {any}\n", .{edges});
            unreachable;
        }
    }
}

pub fn main() !void {
    try fuzz.fuzzer_main(graph_shortest_path_no_longer_than_half);
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
