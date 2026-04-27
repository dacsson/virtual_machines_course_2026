//! Poolp Fiction is a simple single-threaded memory pool allocator
pub const PoolpFictionAllocator = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const posix = std.posix;

pub const vtable: Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

pub const Error = Allocator.Error;

const page_size = std.heap.pageSize();

const default_size = 128 * 1024 * page_size;

/// Start of a mapped memory region for the pool
base: [*]u8 = undefined,
/// Pointer to the free list within the pool,
/// goes "downwards" in memory
free_list: [*]u8 = undefined,
capacity: usize = 0,

/// Initializes a PoolpFictionAllocator with the requested size
///
/// Uses `mmap` to allocate memory, which will grow downwards
/// If `requested_size` is 0, the default size is used
pub fn init(requested_size: ?usize) Error!PoolpFictionAllocator {
    const mem_size = alignToPage(requested_size orelse default_size);
    const total_size = mem_size + page_size; // extra guard page (protected)

    const mem = posix.mmap(
        null,
        total_size,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch return Error.OutOfMemory;

    // any access on first page means pool overflow
    const rc = std.os.linux.mprotect(mem.ptr, page_size, .{ .READ = false, .WRITE = false });
    if (rc != 0) {
        std.debug.print("Memory pool hit the guard page, memory overflow, requested size: {}", .{requested_size orelse default_size});
        return Error.OutOfMemory;
    }

    return .{
        .base = mem.ptr + page_size, // usable region starts after the guard page
        .free_list = mem.ptr + total_size,
        .capacity = total_size,
    };
}

/// Frees the memory allocated by this allocator by unmapping it
pub fn destroyPool(self: *PoolpFictionAllocator) void {
    // base points past the guard page, so unmap from one page before
    posix.munmap(@alignCast((self.base - page_size)[0..self.capacity]));
    self.* = .{};
}

pub fn allocator(self: *PoolpFictionAllocator) Allocator {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, return_address: usize) ?[*]u8 {
    _ = return_address;

    const self: *PoolpFictionAllocator = @ptrCast(@alignCast(ctx));
    const align_val = alignment.toByteUnits();

    const current = @intFromPtr(self.free_list);
    const base = @intFromPtr(self.base);

    const aligned = std.mem.alignBackward(usize, current - len, align_val);
    if (aligned < base) {
        std.debug.print("Memory pool hit the guard page, memory overflow, requested size: {} vs {}", .{ len, current - len });
        return null;
    }

    self.free_list = @ptrFromInt(aligned);
    return self.free_list;
}

fn resize(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, return_address: usize) bool {
    _ = ctx;
    _ = buf;
    _ = alignment;
    _ = new_len;
    _ = return_address;
    return false;
}

fn remap(context: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, return_address: usize) ?[*]u8 {
    _ = context;
    _ = memory;
    _ = alignment;
    _ = new_len;
    _ = return_address;
    return null;
}

fn free(ctx: *anyopaque, buf: []u8, alignment: Alignment, return_address: usize) void {
    _ = ctx;
    _ = buf;
    _ = alignment;
    _ = return_address;
}

fn alignToPage(len: usize) usize {
    return (len + page_size - 1) / page_size * page_size;
}
