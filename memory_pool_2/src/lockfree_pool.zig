/// Global non-blocking (lock-free) pool allocator
///
/// A single instance is shared across all threads
/// Uses @atomicRmw(.Sub), so no lock is ever held
pub const LockFreePoolAllocator = @This();

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const pool_registry = @import("pool_registry.zig");

const page_size = std.heap.pageSize();

/// Start of a mapped memory region for the pool
base: [*]u8 = undefined,
/// Pointer to the free list within the pool,
/// goes "downwards" in memory
free_list: [*]u8 = undefined,
capacity: usize = 0,
/// Slot index in the global pool_registry
slot: usize = 0,

pub fn init(comptime T: type, capacity: usize) std.mem.Allocator.Error!LockFreePoolAllocator {
    const m = try pool_registry.initPool(T, capacity);
    return .{
        .base = m.base,
        .free_list = @ptrFromInt(m.end),
        .capacity = m.capacity,
        .slot = m.slot,
    };
}

/// Uses atomic fetch-subtract to reserve space
pub fn bump(self: *LockFreePoolAllocator, comptime T: type) *T {
    // NOTE: fetch_sub returns the *old* value. the new slot starts at old - sizeof(T)
    const ptr: *usize = @ptrCast(&self.free_list);
    const old = @atomicRmw(usize, ptr, .Sub, @sizeOf(T), .monotonic);
    return @ptrFromInt(old - @sizeOf(T));
}
