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
    const mem_size = alignToPage(requested_size orelse default_size);
    // guard region must be at least te sizeof some el. type so a
    // single bump cannot skip over it, like if it was just a page
    const guard_size = alignToPage(@sizeOf(T));
    const total_size = mem_size + guard_size;

    const mem = posix.mmap(
        null,
        total_size,
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
    if (rc != 0) return Error.OutOfMemory;

    const begin = @intFromPtr(mem.ptr);
    const end = begin + total_size;
    const slot = pool_registry.add(begin, end) orelse return Error.OutOfMemory;

    return .{
        .base = mem.ptr, // guard page in included, so we can detect overflow
        .free_list = mem.ptr + total_size,
        .capacity = total_size,
        .slot = slot,
    };
}

/// Frees the memory allocated by this allocator by unmapping it
pub fn destroyPool(self: *PoolpFictionAllocator) void {
    pool_registry.remove(self.slot);
    posix.munmap(@alignCast(self.base[0..self.capacity]));
    self.* = .{};
}

pub fn bump(self: *PoolpFictionAllocator, comptime T: type) *T {
    const current = @intFromPtr(self.free_list);
    const aligned = std.mem.alignBackward(usize, current - @sizeOf(T), @alignOf(T));
    self.free_list = @ptrFromInt(aligned);
    return @ptrFromInt(aligned);
}

fn alignToPage(len: usize) usize {
    return (len + page_size - 1) / page_size * page_size;
}
