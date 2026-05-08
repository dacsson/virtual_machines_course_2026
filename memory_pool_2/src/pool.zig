/// See ../memory_pool/src/pool.zig
pub const PoolpFictionAllocator = @This();

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const pool_registry = @import("pool_registry.zig");

pub const Error = std.mem.Allocator.Error;

const page_size = std.heap.pageSize();

const default_size = 128 * 1024 * page_size;

/// Start of a mapped memory region for the pool
base: [*]u8 = undefined,
/// Pointer to the free list within the pool,
/// goes "downwards" in memory
free_list: [*]u8 = undefined,
capacity: usize = 0,
/// Slot index in the global pool_registry
slot: usize = 0,

/// Initializes a PoolpFictionAllocator with the requested size
///
/// Uses `mmap` to allocate memory, which will grow downwards
/// If `requested_size` is 0, the default size is used
pub fn init(comptime T: type, requested_size: ?usize) Error!PoolpFictionAllocator {
    const size = requested_size orelse default_size;
    // convert bytes to element count for initPool
    const capacity = size / @sizeOf(T);
    const m = try pool_registry.initPool(T, capacity);
    return .{
        .base = m.base,
        .free_list = @ptrFromInt(m.end),
        .capacity = m.capacity,
        .slot = m.slot,
    };
}

pub fn bump(self: *PoolpFictionAllocator, comptime T: type) *T {
    const current = @intFromPtr(self.free_list);
    const aligned = std.mem.alignBackward(usize, current - @sizeOf(T), @alignOf(T));
    self.free_list = @ptrFromInt(aligned);
    return @ptrFromInt(aligned);
}
