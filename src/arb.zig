const std = @import("std");
const assert = std.debug.assert;

const test_data = @import("./test_data.zig");
const TestData = test_data.TestData;

/// Draw an enum value from `E` based on the relative `weights`. Fields in the weights struct must match
/// the enum.
///
/// The `E` type parameter should be inferred, but seemingly to due to https://github.com/ziglang/zig/issues/19985,
/// it can't be.
pub fn weighted(comptime E: type, comptime weights: std.enums.EnumFieldStruct(E, u32, null), data: *TestData) !E {
    const s = @typeInfo(@TypeOf(weights)).Struct;
    comptime var total: u64 = 0;
    comptime var enum_weights: [s.fields.len]std.meta.Tuple(&.{ E, comptime_int }) = undefined;

    comptime {
        for (s.fields, 0..) |field, i| {
            const weight: comptime_int = @field(weights, field.name);
            assert(weight > 0);
            total += weight;
            const value = std.meta.stringToEnum(E, field.name).?;
            enum_weights[i] = .{ value, weight };
        }
    }

    const pick = try bounded_int(u64, 1, total + 1, data);
    var current: u64 = 0;
    inline for (enum_weights) |w| {
        current += w[1];
        if (pick <= current) {
            return w[0];
        }
    }
    unreachable;
}

pub fn boolean(data: *TestData) !bool {
    var bytes: [1]u8 = undefined;
    try data.draw(1, &bytes);
    return (bytes[0] & 1) == 1;
}

pub fn byte(data: *TestData) !u8 {
    var bytes: [1]u8 = undefined;
    try data.draw(1, &bytes);
    return bytes[0];
}

pub fn int(T: type, data: *TestData) !T {
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
pub fn bounded_int(comptime T: type, start: T, end: T, data: *TestData) !T {
    assert(start < end);
    const diff = end - start;
    return ((try int(T, data)) % diff) + start;
}

pub fn enum_value(T: type, data: *TestData) !T {
    comptime var values: [@typeInfo(T).Enum.fields.len]usize = undefined;
    inline for (@typeInfo(T).Enum.fields, 0..) |field, i| {
        values[i] = field.value;
    }
    const index = try bounded_int(usize, 0, values.len, data);
    const value = values[index];
    return @enumFromInt(value);
}
