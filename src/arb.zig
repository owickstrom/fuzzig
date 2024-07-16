const std = @import("std");
const assert = std.debug.assert;

const test_data = @import("./test_data.zig");
const TestData = test_data.TestData;

fn Weighted(T: type) type {
    return struct { u32, T };
}

pub fn Arb(T: type) type {
    return struct {
        const Self = @This();
        drawFn: fn (self: *Self, td: *TestData, allocator: std.mem.Allocator) anyerror!T,
        pub fn draw(self: *Self, td: *TestData, allocator: std.mem.Allocator) !T {
            return self.drawFn(self, td, allocator);
        }
    };
}

const BoolArb = struct {
    arb: Arb(bool) = .{
        .drawFn = draw,
    },
    pub fn draw(_: *Arb(bool), data: *TestData, _: std.mem.Allocator) !bool {
        const bytes: [1]u8 = undefined;
        try data.draw(1, bytes);
        return (bytes[0] & 1) == 1;
    }
};

fn IntArb(T: type) type {
    return struct {
        arb: Arb(T) = .{
            .drawFn = draw,
        },
        pub fn draw(_: *Arb(T), data: *TestData, _: std.mem.Allocator) !T {
            const bit_count = @typeInfo(T).Int.bits;
            const byte_count = bit_count / 8;
            var bytes: [byte_count]u8 = undefined;
            try data.draw(byte_count, &bytes);
            const result = std.mem.readInt(T, &bytes, .big);
            if (@rem(bit_count, 64) == 0) {
                return result;
            } else {
                const mask = (1 << bit_count) - 1;
                return result & mask;
            }
        }
    };
}

const ByteArb = struct {
    arb: Arb(u8) = .{
        .drawFn = draw,
    },
    pub fn draw(_: *Arb(u8), data: *TestData, _: std.mem.Allocator) !u8 {
        const bytes: [1]u8 = undefined;
        try data.draw(1, bytes);
        return bytes[0];
    }
};

fn BoundedIntArb(T: type) type {
    return struct {
        start: T,
        end: T,
        arb: Arb(T) = .{
            .drawFn = draw,
        },
        pub fn draw(arb: *Arb(T), data: *TestData, allocator: std.mem.Allocator) !T {
            const self: *@This() = @alignCast(@fieldParentPtr("arb", arb));
            assert(self.start < self.end);
            const diff = self.end - self.start;
            return ((try Arbs.int(T).draw(data, allocator)) % diff) + self.start;
        }
    };
}

fn SliceArb(T: type) type {
    return struct {
        value_arb: *Arb(T),
        min_length: usize,
        max_length: usize,
        arb: Arb([]T) = .{
            .drawFn = draw,
        },
        pub fn draw(arb: *Arb([]T), data: *TestData, allocator: std.mem.Allocator) ![]T {
            const self: *@This() = @alignCast(@fieldParentPtr("arb", arb));
            comptime {
                assert(self.min_length >= 0);
                assert(self.min_length <= self.max_length);
            }

            // TODO: pick a random length or pick bools continously to check whether to continue generating?
            var result = try allocator.alloc(T, self.max_length);
            for (0..self.max_length) |i| {
                if (self.value_arb.draw(data, allocator)) |value| {
                    result[i] = value;
                } else |_| {
                    if (i < self.min_length) {
                        return error.OutOfEntropy;
                    } else {
                        return result[0..i];
                    }
                }
            }
            return result[0..self.max_length];
        }
    };
}

fn FrequenciesArb(T: type) type {
    return struct {
        weights: []const Weighted(*Arb(T)),
        arb: Arb(T) = .{
            .drawFn = draw,
        },
        pub fn draw(arb: *Arb(T), data: *TestData, allocator: std.mem.Allocator) !T {
            const self: *@This() = @alignCast(@fieldParentPtr("arb", arb));
            comptime var total: u64 = 0;

            comptime {
                for (self.weights) |weighted| {
                    assert(weighted[0] > 0);
                    total += weighted[0];
                }
            }

            const pick = try Arbs.bounded_int(u64, 0, total).draw(data, allocator);
            var current: u64 = 0;
            inline for (self.weights) |weighted| {
                current += weighted[0];
                if (pick < current) {
                    return weighted[1].draw(data, allocator);
                }
            }
            unreachable;
        }
    };
}

fn ConstantArb(T: type, value: T) type {
    return struct {
        arb: Arb(T) = .{
            .drawFn = draw,
        },
        pub fn draw(_: *Arb(T), _: *TestData, _: std.mem.Allocator) !T {
            return value;
        }
    };
}

fn EnumArb(T: type) type {
    return struct {
        arb: Arb(T) = .{
            .drawFn = draw,
        },
        pub fn draw(_: *Arb(T), data: *TestData, allocator: std.mem.Allocator) !T {
            comptime var values: [@typeInfo(T).Enum.fields.len]usize = undefined;
            inline for (@typeInfo(T).Enum.fields, 0..) |field, i| {
                values[i] = field.value;
            }
            const index = try Arbs.bounded_int(usize, 0, values.len).draw(data, allocator);
            const value = values[index];
            return @enumFromInt(value);
        }
    };
}

fn FromFnArb(T: type, drawFn: fn (td: *TestData, allocator: std.mem.Allocator) anyerror!T) type {
    return struct {
        arb: Arb(T) = .{
            .drawFn = draw,
        },
        pub fn draw(_: *Arb(T), data: *TestData, allocator: std.mem.Allocator) !T {
            return drawFn(data, allocator);
        }
    };
}

pub const Arbs = struct {
    pub fn boolean() *Arb(bool) {
        return @constCast(&(BoolArb{}).arb);
    }

    pub fn byte() *Arb(u8) {
        return @constCast(&(ByteArb{}).arb);
    }

    pub fn int(T: type) *Arb(T) {
        return @constCast(&(IntArb(T){}).arb);
    }

    /// Draw an integer of type `T` between `start` (incl) and `end` (excl).
    pub fn bounded_int(comptime T: type, start: T, end: T) *Arb(T) {
        return @constCast(&(BoundedIntArb(T){ .start = start, .end = end }).arb);
    }

    pub fn slice(T: type, value_arb: *Arb(T), min_length: usize, max_length: usize) *Arb([]T) {
        // TODO: Pass in allocator? Or put all of these helpers in a struct with an allocator field?
        return @constCast(&(SliceArb(T){ .value_arb = value_arb, .min_length = min_length, .max_length = max_length }).arb);
    }

    pub fn frequencies(T: type, weights: []const Weighted(*Arb(T))) *Arb(T) {
        return @constCast(&(FrequenciesArb(T){ .weights = weights }).arb);
    }

    pub fn constant(T: type, value: T) *Arb(T) {
        return @constCast(&(ConstantArb(T, value){}).arb);
    }

    pub fn enum_value(T: type) *Arb(T) {
        return @constCast(&(EnumArb(T){}).arb);
    }

    pub fn from_fn(
        T: type,
        f: fn (td: *TestData, allocator: std.mem.Allocator) anyerror!T,
    ) *Arb(T) {
        return @constCast(&(FromFnArb(T, f){}).arb);
    }
};
