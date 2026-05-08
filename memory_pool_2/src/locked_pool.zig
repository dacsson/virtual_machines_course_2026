/// Global pool allocator protected by a mutex
///
/// A single instance is shared across all threads
/// Each bump() call acquires a std.Io.Mutex, decrements the free pointer, and releases the lock
pub const LockedPoolAllocator = @This();

const std = @import("std");
const Io = std.Io;
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
/// mutex protecting the bump pointer
mutex: Io.Mutex = Io.Mutex.init,

pub fn init(comptime T: type, capacity: usize) std.mem.Allocator.Error!LockedPoolAllocator {
    const m = try pool_registry.initPool(T, capacity);
    return .{
        .base = m.base,
        .free_list = @ptrFromInt(m.end),
        .capacity = m.capacity,
        .slot = m.slot,
    };
}

pub fn bump(self: *LockedPoolAllocator, comptime T: type, io: Io) *T {
    self.mutex.lockUncancelable(io);
    defer self.mutex.unlock(io);
    const current = @intFromPtr(self.free_list);
    const new_ptr = current - @sizeOf(T);
    self.free_list = @ptrFromInt(new_ptr);
    return @ptrFromInt(new_ptr);
}
