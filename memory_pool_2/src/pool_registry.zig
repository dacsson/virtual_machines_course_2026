/// Global pool registry and SIGSEGV handler
///
/// Every allogator registers its address range here on creation
/// When a SIGSEGV fires, the handler walks the registry to report which pool overflowed, then dips
///
/// Registration is lock-free: slots are claimed with @cmpxchgStrong on the
/// `begin` field (0 is free slot)
const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const pool_limit: usize = 256;

const PoolEntry = struct {
    /// Start address of the mmapd region (0 = slot is free)
    begin: usize = 0,
    /// End address (begin + total_size)
    end: usize = 0,
};

/// Registry of known pool address ranges
/// NOTE: Accessed atomically
var known_pools: [pool_limit]PoolEntry = @splat(.{});

/// Saved previous SIGSEGV handler forwarded to if the fault is not mine
var old_act: posix.Sigaction = undefined;

const page_size = std.heap.pageSize();

/// Register a pools address range
/// Returns a slot index on success
/// or null if all 256 slots are taken
pub fn add(begin: usize, end: usize) ?usize {
    for (&known_pools, 0..) |*entry, i| {
        if (@cmpxchgStrong(usize, &entry.begin, 0, begin, .monotonic, .monotonic) == null) {
            @atomicStore(usize, &entry.end, end, .monotonic);
            return i;
        }
    }
    return null;
}

pub fn remove(slot: usize) void {
    @atomicStore(usize, &known_pools[slot].begin, 0, .monotonic);
}

pub fn installHandler() void {
    const act: posix.Sigaction = .{
        .handler = .{ .sigaction = &sigsegvHandler },
        .mask = std.mem.zeroes(std.c.sigset_t),
        .flags = linux.SA.SIGINFO,
    };
    posix.sigaction(linux.SIG.SEGV, &act, &old_act);
}

fn writeStr(s: []const u8) void {
    _ = posix.system.write(2, s.ptr, s.len);
}

fn writeHex(value: usize) void {
    var buf: [2 * @sizeOf(usize)]u8 = undefined;
    var v = value;
    var i: usize = buf.len;
    while (i > 0) {
        i -= 1;
        const digit: u8 = @truncate(v & 0xf);
        buf[i] = if (digit < 10) '0' + digit else 'a' + digit - 10;
        v >>= 4;
    }
    writeStr(&buf);
}

fn sigsegvHandler(sig: linux.SIG, info: *const linux.siginfo_t, ctx: ?*anyopaque) callconv(.c) void {
    const fault_addr = @intFromPtr(info.fields.sigfault.addr);

    for (&known_pools) |*entry| {
        const begin = @atomicLoad(usize, &entry.begin, .monotonic);
        if (begin != 0 and begin <= fault_addr) {
            const end = @atomicLoad(usize, &entry.end, .monotonic);
            if (fault_addr < end) {
                writeStr("Bad alloc in PoolAllocator: pool begins at 0x");
                writeHex(begin);
                writeStr("\n");
                std.process.exit(3);
            }
        }
    }

    // not my fault man
    posix.sigaction(linux.SIG.SEGV, &old_act, null);
    if (old_act.handler.sigaction) |handler| {
        handler(sig, info, ctx);
    }
}

pub fn alignToPage(len: usize) usize {
    return (len + page_size - 1) / page_size * page_size;
}

/// Common fields returned by initPool, used by each allocator to
/// construct itself
pub const PoolMemory = struct {
    base: [*]u8,
    end: usize,
    capacity: usize,
    slot: usize,
};

/// mmap a pool region with guard pages and register it
/// `capacity` is the number of elements of type T
pub fn initPool(comptime T: type, capacity: usize) std.mem.Allocator.Error!PoolMemory {
    const guard_size = alignToPage(@sizeOf(T));
    const pool_size = alignToPage(guard_size + capacity * @sizeOf(T));

    const mem = posix.mmap(
        null,
        pool_size,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch return error.OutOfMemory;

    const rc = linux.mprotect(mem.ptr, guard_size, .{ .READ = false, .WRITE = false });
    if (rc != 0) return error.OutOfMemory;

    const begin = @intFromPtr(mem.ptr);
    const end = begin + pool_size;
    const slot = add(begin, end) orelse return error.OutOfMemory;

    return .{
        .base = mem.ptr,
        .end = end,
        .capacity = pool_size,
        .slot = slot,
    };
}

/// Frees the memory allocated by this allocator by unmapping it
pub fn destroyPool(pool: anytype) void {
    remove(pool.slot);
    posix.munmap(@alignCast(pool.base[0..pool.capacity]));
    pool.* = .{};
}
