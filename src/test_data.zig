const std = @import("std");
const assert = std.debug.assert;

pub const DrawError = error{OutOfEntropy};

/// Calculate how many bytes to allocate in order to fit a given number of bits.
pub fn required_bytes(bits: u64) u64 {
    if (@rem(bits, 8) == 0) {
        return @divExact(bits, 8);
    } else {
        return std.math.divCeil(u64, bits, 8) catch |e| {
            @compileError("can't calculate required bytes for bits: " ++ @typeName(e));
        };
    }
}

comptime {
    assert(required_bytes(16) == 2);
    assert(required_bytes(9) == 2);
    assert(required_bytes(8) == 1);
    assert(required_bytes(7) == 1);
    assert(required_bytes(0) == 0);
}

pub const TestData = struct {
    entropy: []u8,
    cursor: usize,

    pub fn draw(self: *@This(), comptime bytes: u64, result: *[bytes]u8) !void {
        comptime {
            assert(bytes > 0);
        }
        if (self.cursor + bytes > self.entropy.len) {
            return error.OutOfEntropy;
        }

        std.mem.copyForwards(u8, result, self.entropy[self.cursor .. self.cursor + bytes]);
        self.cursor += bytes;
    }

    /// Returns the entropy used (up to the cursor).
    pub fn trimmed(self: *@This()) []u8 {
        return self.entropy[0..self.cursor];
    }

    pub fn init(allocator: std.mem.Allocator, entropy: []u8) !*@This() {
        const result = try allocator.create(TestData);
        result.entropy = entropy;
        result.cursor = 0;
        return result;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub fn random_bytes(allocator: std.mem.Allocator, buf_size: usize, seed: u64) ![]u8 {
    var prng = std.rand.DefaultPrng.init(seed);
    const entropy = try allocator.alloc(u8, buf_size);
    prng.random().bytes(entropy);
    return entropy;
}
