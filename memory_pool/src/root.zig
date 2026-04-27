const std = @import("std");
const Allocator = std.mem.Allocator;

// Default implementation mirroring  doc/test.cc
const benchmark = @import("benchmark.zig");
pub const benchmarkDefaultList = benchmark.benchmarkList;

pub const PoolpFictionAllocator = @import("pool.zig");

/// Create a pool-backed allocator with the given capacity.
pub fn poolpFictionAllocator(size: ?usize) PoolpFictionAllocator.Error!PoolpFictionAllocator {
    return PoolpFictionAllocator.init(size);
}
