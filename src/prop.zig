const std = @import("std");
const assert = std.debug.assert;

const test_data = @import("./test_data.zig");
const TestData = test_data.TestData;

const Arb = @import("./arb.zig").Arb;

const PropTestConfig = struct {
    size: ?usize = null,
    runs: u32 = 100,
    max_shrinks: u32 = 100,
};

fn random_seed() !u64 {
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    return seed;
}

fn Prop(I: type) type {
    return fn (I) anyerror!void;
}

const PropTestError = error{PropTestFailed};

// TODO: package this up in a struct that holds the allocator and config?

pub fn prop_test(I: type, allocator: std.mem.Allocator, config: PropTestConfig, arb_input: *Arb(I), prop: Prop(I)) !void {
    const size = config.size orelse 1024;

    for (0..config.runs) |i| {
        const seed = try random_seed();

        const entropy = try test_data.random_bytes(allocator, size, seed);
        defer allocator.free(entropy);

        var td = try TestData.init(allocator, entropy);
        defer td.deinit(allocator);

        const input = try arb_input.draw(td, allocator);

        if (prop(input)) |_| {} else |err| {
            const counter_example =
                try shrink(I, allocator, config, td, arb_input, prop) orelse
                CounterExample(I){ .num = 0, .entropy = entropy, .input = input, .err = err };
            std.debug.print("original entropy: {}\n", .{std.fmt.fmtSliceHexLower(entropy)});
            std.debug.print("\noriginal input: {any}\n", .{input});
            std.debug.print("failed after {} run(s) and {} shrink(s)!\n", .{ i + 1, counter_example.num });
            if (counter_example.num > 0) {
                std.debug.print("shrunk entropy: {}\n", .{std.fmt.fmtSliceHexLower(counter_example.entropy)});
                std.debug.print("shrunk input: {any}\n", .{counter_example.input});
            }
            return counter_example.err;
        }
    }
}

const CandidatesQueue = std.fifo.LinearFifo([]u8, .Dynamic);

fn CounterExample(T: type) type {
    return struct {
        num: u32,
        entropy: []u8,
        input: T,
        err: anyerror,
    };
}

fn add_smaller(allocator: std.mem.Allocator, entropy: []u8, queue: *CandidatesQueue) !void {
    if (entropy.len > 1 and @mod(entropy.len, 2) == 0) {
        // First half
        try queue.writeItem(entropy[entropy.len / 2 .. entropy.len]);

        // Second half
        try queue.writeItem(entropy[0 .. entropy.len / 2]);

        // Divide first half's bytes by two
        {
            const entropy_new = try allocator.alloc(u8, entropy.len);
            @memcpy(entropy_new, entropy);
            for (0..entropy_new.len / 2) |i| {
                entropy_new[i] = entropy_new[i] / 2;
            }
            try queue.writeItem(entropy_new);
        }

        // Divide last half's bytes by two
        {
            const entropy_new = try allocator.alloc(u8, entropy.len);
            @memcpy(entropy_new, entropy);
            for (entropy_new.len / 2..entropy.len) |i| {
                entropy_new[i] = entropy_new[i] / 2;
            }
            try queue.writeItem(entropy_new);
        }
    }
    if (entropy.len > 0) {
        // Drop first
        try queue.writeItem(entropy[1..entropy.len]);

        // Drop last
        try queue.writeItem(entropy[0 .. entropy.len - 1]);
    }
}

/// Compares to entropy buffers in terms of "test size".
///
/// Buffer lenght is most significant. After that, we use lexicographic byte order for equal-length buffers.
fn is_smaller_than(left: []u8, right: []u8) bool {
    if (left.len < right.len) {
        return true;
    } else if (left.len > right.len) {
        return false;
    } else {
        for (left, right) |b1, b2| {
            if (b1 < b2) {
                return true;
            }
        }
        return false;
    }
}

fn shrink(T: type, allocator: std.mem.Allocator, config: PropTestConfig, data: *TestData, arb_input: *Arb(T), prop: Prop(T)) !?CounterExample(T) {
    // TODO: tree of candidates (maybe ranges into the original entropy)?
    var candidates: CandidatesQueue = CandidatesQueue.init(allocator);
    defer candidates.deinit();

    // We always start by shrinking the original input. Note that it's first trimmed, meaning
    // that all unused entropy is discarded straight away.
    try add_smaller(allocator, data.trimmed(), &candidates);

    var counter_example_smallest: ?CounterExample(T) = null;
    for (0..config.max_shrinks) |shrink_index| {
        const candidate = candidates.readItem() orelse {
            // No more candidates available.
            break;
        };

        var shorter_data = try TestData.init(allocator, candidate);
        defer shorter_data.deinit(allocator);

        const input = arb_input.draw(shorter_data, allocator) catch {
            // If we can't draw, the entropy has probably been shrunk too much.
            break;
        };
        if (prop(input)) |_| {
            // This candidate doesn't fail the property, so we continue searching for other (smaller) inputs.
            continue;
        } else |err| {
            const counter_example_new: CounterExample(T) =
                .{ .num = @intCast(shrink_index + 1), .entropy = candidate, .input = input, .err = err };
            if (counter_example_smallest) |counter_example_old| {
                if (is_smaller_than(counter_example_new.entropy, counter_example_old.entropy)) {
                    counter_example_smallest = counter_example_new;
                }
            } else {
                counter_example_smallest = counter_example_new;
            }
            try add_smaller(allocator, candidate, &candidates);
        }
    }

    return counter_example_smallest;
}
