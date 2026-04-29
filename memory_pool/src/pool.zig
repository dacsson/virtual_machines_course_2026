pub const PoolpFictionAllocator = @This();

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

pub const Error = std.mem.Allocator.Error;

const page_size = std.heap.pageSize();

const default_size = 128 * 1024 * page_size;

/// Start of a mapped memory region for the pool
base: [*]u8 = undefined,
/// Pointer to the free list within the pool,
/// goes "downwards" in memory
free_list: [*]u8 = undefined,
capacity: usize = 0,

/// We use this in the signal handler to specify error
var guard_page_start: usize = 0;
var guard_page_end: usize = 0;
var old_act: posix.Sigaction = undefined;

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
    ) catch return Error.OutOfMemory;

    const rc = linux.mprotect(mem.ptr, guard_size, .{ .READ = false, .WRITE = false });
    if (rc != 0) return Error.OutOfMemory;

    guard_page_start = @intFromPtr(mem.ptr);
    guard_page_end = guard_page_start + guard_size;

    const act: posix.Sigaction = .{
        .handler = .{ .sigaction = &sigsegvHandler },
        .mask = std.mem.zeroes(std.c.sigset_t),
        .flags = linux.SA.SIGINFO,
    };
    posix.sigaction(linux.SIG.SEGV, &act, &old_act);

    return .{
        .base = mem.ptr, // guard page in included, so we can detect overflow
        .free_list = mem.ptr + total_size,
        .capacity = total_size,
    };
}

/// Frees the memory allocated by this allocator by unmapping it
pub fn destroyPool(self: *PoolpFictionAllocator) void {
    posix.munmap(@alignCast(self.base[0..self.capacity]));
    self.* = .{};
}

pub fn bump(self: *PoolpFictionAllocator, comptime T: type) *T {
    const current = @intFromPtr(self.free_list);
    const aligned = std.mem.alignBackward(usize, current - @sizeOf(T), @alignOf(T));
    self.free_list = @ptrFromInt(aligned);
    return @ptrFromInt(aligned);
}

fn sigsegvHandler(sig: linux.SIG, info: *const linux.siginfo_t, ctx: ?*anyopaque) callconv(.c) void {
    const fault_addr = @intFromPtr(info.fields.sigfault.addr);
    if (fault_addr >= guard_page_start and fault_addr < guard_page_end) {
        const msg = "Memory pool overflow: write hit the guard page\n";
        _ = posix.system.write(2, msg.ptr, msg.len);
        std.process.exit(1);
    }

    posix.sigaction(linux.SIG.SEGV, &old_act, null);
    if (old_act.handler.sigaction) |handler| {
        handler(sig, info, ctx);
    }
}

fn alignToPage(len: usize) usize {
    return (len + page_size - 1) / page_size * page_size;
}
