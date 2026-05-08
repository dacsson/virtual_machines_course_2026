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
    const guard_size = alignToPage(@sizeOf(T));
    const pool_size = alignToPage(guard_size + capacity * @sizeOf(T));

    const mem = posix.mmap(
        null,
        pool_size,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch |err| {
        switch (err) {
            error.MemoryMappingNotSupported => std.debug.panic("MemoryMappingNotSupported: {}", .{err}),
            error.AccessDenied => std.debug.panic("AccessDenied: {}", .{err}),
            error.PermissionDenied => std.debug.panic("PermissionDenied: {}", .{err}),
            else => |e| {
                return e;
            },
        }
    };

    const rc = linux.mprotect(mem.ptr, guard_size, .{ .READ = false, .WRITE = false });
    if (rc != 0) return error.OutOfMemory;

    const begin = @intFromPtr(mem.ptr);
    const end = begin + pool_size;
    const slot = pool_registry.add(begin, end) orelse return error.OutOfMemory;

    return .{
        .base = mem.ptr,
        .free_list = end,
        .capacity = pool_size,
        .slot = slot,
    };
}

/// Uses atomic fetch-subtract to reserve space
pub fn bump(self: *LockFreePoolAllocator, comptime T: type) *T {
    // NOTE: fetch_sub returns the *old* value. the new slot starts at old - sizeof(T)
    const old = @atomicRmw(usize, &self.free_list, .Sub, @sizeOf(T), .monotonic);
    return @ptrFromInt(old - @sizeOf(T));
}

pub fn destroy(self: *LockFreePoolAllocator) void {
    pool_registry.remove(self.slot);
    posix.munmap(@alignCast(self.base[0..self.capacity]));
    self.* = .{};
}

fn alignToPage(len: usize) usize {
    return (len + page_size - 1) / page_size * page_size;
}
