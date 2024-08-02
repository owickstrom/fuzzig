const std = @import("std");
const assert = std.debug.assert;

const test_data = @import("./test_data.zig");
const TestData = test_data.TestData;

// pub fn draw(arb: *Arb(T), data: *TestData, allocator: std.mem.Allocator) !T {
//     const self: *@This() = @alignCast(@fieldParentPtr("arb", arb));
//     comptime var total: u64 = 0;
//
//     comptime {
//         for (self.weights) |weighted| {
//             assert(weighted[0] > 0);
//             total += weighted[0];
//         }
//     }
//
//     const pick = try bounded_int(u64, 0, total).draw(data, allocator);
//     var current: u64 = 0;
//     inline for (self.weights) |weighted| {
//         current += weighted[0];
//         if (pick < current) {
//             return weighted[1].draw(data, allocator);
//         }
//     }
//     unreachable;
// }

fn weighted_tag_type(weights: anytype) type {
    switch (@typeInfo(@TypeOf(weights))) {
        .Struct => |_| {},
        else => |info| @compileError("weights must be a struct, where each field type is an unsigned integer, but was " ++ info),
    }
    return std.meta.FieldEnum(@TypeOf(weights));
}

pub fn weighted(comptime weights: anytype, data: *TestData) !weighted_tag_type(weights) {
    const s = switch (@typeInfo(@TypeOf(weights))) {
        .Struct => |s| s,
        else => @compileError("weights must be a struct, where each field type is an unsigned integer"),
    };
    const enum_type = std.meta.FieldEnum(@TypeOf(weights));
    comptime var total: u64 = 0;
    comptime var enum_weights: [s.fields.len]std.meta.Tuple(&.{ enum_type, comptime_int }) = undefined;

    comptime {
        for (s.fields, 0..) |field, i| {
            const weight: comptime_int = @field(weights, field.name);
            assert(weight > 0);
            total += weight;
            @compileLog(weights);
            @compileLog(enum_type, field.name);
            const value = std.meta.stringToEnum(enum_type, field.name).?;
            @compileLog(value);
            enum_weights[i] = .{ value, weight };
        }
    }

    const pick = try bounded_int(u64, 0, total, data);
    var current: u64 = 0;
    for (s.fields) |field| {
        current += field.default_value;
        if (pick < current) {
            return enum_value(enum_type, data);
        }
    }
    unreachable;
}

pub fn boolean(data: *TestData) test_data.DrawError!bool {
    const bytes: [1]u8 = undefined;
    try data.draw(1, bytes);
    return (bytes[0] & 1) == 1;
}

pub fn byte(data: *TestData) test_data.DrawError!u8 {
    const bytes: [1]u8 = undefined;
    try data.draw(1, bytes);
    return bytes[0];
}

pub fn int(T: type, data: *TestData) test_data.DrawError!T {
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

/// Draw an integer of type `T` between `start` (incl) and `end` (excl).
pub fn bounded_int(comptime T: type, start: T, end: T, data: *TestData) test_data.DrawError!T {
    assert(start < end);
    const diff = end - start;
    return ((try int(T, data)) % diff) + start;
}

pub fn enum_value(T: type, data: *TestData) test_data.DrawError!T {
    comptime var values: [@typeInfo(T).Enum.fields.len]usize = undefined;
    inline for (@typeInfo(T).Enum.fields, 0..) |field, i| {
        values[i] = field.value;
    }
    const index = try bounded_int(usize, 0, values.len, data);
    const value = values[index];
    return @enumFromInt(value);
}
