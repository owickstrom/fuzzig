const std = @import("std");
const assert = std.debug.assert;

pub const DrawError = error{OutOfEntropy};

pub const TestData =
    struct {
    reader: std.io.AnyReader,
    cursor: usize,

    pub fn draw(self: *@This(), comptime bytes: u64, result: *[bytes]u8) !void {
        comptime {
            assert(bytes > 0);
        }

        const read = try self.reader.read(result);
        if (read < bytes) {
            return error.OutOfEntropy;
        }

        self.cursor += bytes;
    }

    /// Returns the entropy used (up to the cursor).
    pub fn trimmed(self: *@This()) []u8 {
        return self.reader[0..self.cursor];
    }

    pub fn init(allocator: std.mem.Allocator, reader: anytype) !*TestData {
        const result = try allocator.create(TestData);
        result.reader = reader;
        result.cursor = 0;
        return result;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub fn from_reader(allocator: std.mem.Allocator, reader: std.io.AnyReader) !*TestData {
    return TestData.init(allocator, reader);
}

pub fn random_bytes(allocator: std.mem.Allocator, buf_size: usize, seed: u64) ![]u8 {
    var prng = std.rand.DefaultPrng.init(seed);
    const entropy = try allocator.alloc(u8, buf_size);
    prng.random().bytes(entropy);
    return entropy;
}
