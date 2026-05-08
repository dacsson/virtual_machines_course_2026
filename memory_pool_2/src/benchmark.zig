/// Refactored for multi-threading version of [this](../memory_pool/src/benchmark.zig)
///
/// Each benchmark spawns `threads_num` threads
///
/// Allocator variants:
///   - C allocator (malloc/free)      - shared, thread-safe by libc
///   - LockedPoolAllocator            - one shared pool, mutex-protected
///   - LockFreePoolAllocator          - one shared pool, atomic bump
///   - PoolpFictionAllocator (local)  - from ../memory_pool/src/pool.zig
const std = @import("std");
const Io = std.Io;
const PoolpFictionAllocator = @import("pool.zig");
const LockedPoolAllocator = @import("locked_pool.zig");
const LockFreePoolAllocator = @import("lockfree_pool.zig");

pub const threads_num = 16;
pub const nodes_num: usize = 10_000_000;

const Node = struct {
    /// Nullable ptr to next node in list
    next: ?*Node,
    id: usize,
};

/// C alloc
fn heapThread(n: usize) void {
    const allocator = std.heap.c_allocator;
    var list: ?*Node = null;
    for (0..n) |i| {
        const node = allocator.create(Node) catch @panic("c_allocator: alloc failed");
        node.* = .{ .next = list, .id = i };
        list = node;
    }
    var current = list;
    while (current) |node| {
        current = node.next;
        allocator.destroy(node);
    }
}

/// Bencharmk C alloc
pub fn benchmarkHeap(io: Io) !void {
    const start = std.posix.getrusage(std.posix.rusage.SELF);

    var threads: [threads_num]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, heapThread, .{nodes_num});
    }
    for (&threads) |*t| {
        t.*.join();
    }

    const end = std.posix.getrusage(std.posix.rusage.SELF);
    try printStats(io, start, end, nodes_num * threads_num);
}

/// Build a linked list bumping from a shared locked pool
/// pool is freed in bulk after all threads join
fn lockedPoolThread(pool: *LockedPoolAllocator, n: usize, io: Io) void {
    var list: ?*Node = null;
    for (0..n) |i| {
        const node = pool.bump(Node, io);
        node.* = .{ .next = list, .id = i };
        list = node;
    }
}

pub fn benchmarkLockedPool(io: Io) !void {
    const start = std.posix.getrusage(std.posix.rusage.SELF);

    var pool = try LockedPoolAllocator.init(Node, nodes_num * threads_num);

    var threads: [threads_num]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, lockedPoolThread, .{ &pool, nodes_num, io });
    }
    for (&threads) |*t| {
        t.*.join();
    }

    pool.destroy();

    const end = std.posix.getrusage(std.posix.rusage.SELF);
    try printStats(io, start, end, nodes_num * threads_num);
}

/// Bumping from a shared lock-free pool.
fn lockFreePoolThread(pool: *LockFreePoolAllocator, n: usize) void {
    var list: ?*Node = null;
    for (0..n) |i| {
        const node = pool.bump(Node);
        node.* = .{ .next = list, .id = i };
        list = node;
    }
}

pub fn benchmarkLockFreePool(io: Io) !void {
    const start = std.posix.getrusage(std.posix.rusage.SELF);

    var pool = try LockFreePoolAllocator.init(Node, nodes_num * threads_num);

    var threads: [threads_num]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, lockFreePoolThread, .{ &pool, nodes_num });
    }
    for (&threads) |*t| {
        t.*.join();
    }

    pool.destroy();

    const end = std.posix.getrusage(std.posix.rusage.SELF);
    try printStats(io, start, end, nodes_num * threads_num);
}

/// Simple dimple: each thread creates its own pool, builds a list, then
/// destroys the pool
/// No synch
fn localPoolThread(n: usize) void {
    var pool = PoolpFictionAllocator.init(Node, n * @sizeOf(Node)) catch
        @panic("local pool: init failed");
    defer pool.destroyPool();

    var list: ?*Node = null;
    for (0..n) |i| {
        const node = pool.bump(Node);
        node.* = .{ .next = list, .id = i };
        list = node;
    }
}

pub fn benchmarkLocalPool(io: Io) !void {
    const start = std.posix.getrusage(std.posix.rusage.SELF);

    var threads: [threads_num]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, localPoolThread, .{nodes_num});
    }
    for (&threads) |*t| {
        t.*.join();
    }

    const end = std.posix.getrusage(std.posix.rusage.SELF);
    try printStats(io, start, end, nodes_num * threads_num);
}

/// For error message testing, allocates a pool that is too small
pub fn benchmarkOverflow(_: Io) void {
    const page_size = std.heap.pageSize();
    var pool = PoolpFictionAllocator.init(Node, page_size) catch
        @panic("overflow test: pool init failed");
    defer pool.destroyPool();

    var list: ?*Node = null;
    for (0..nodes_num) |i| {
        const node = pool.bump(Node);
        node.* = .{ .next = list, .id = i };
        list = node;
    }
}

fn timevalDiff(a: std.posix.timeval, b: std.posix.timeval) std.posix.timeval {
    var sec = a.sec - b.sec;
    var usec = a.usec - b.usec;

    if (usec < 0) {
        sec -= 1;
        usec += std.time.us_per_s;
    }

    return .{
        .sec = sec,
        .usec = usec,
    };
}

fn timevalToUsec(time: std.posix.timeval) i64 {
    const usec = time.usec;
    const sec: i64 = @intCast(time.sec);
    return sec * std.time.us_per_s + usec;
}

fn printStats(io: Io, start: std.posix.rusage, end: std.posix.rusage, n: usize) !void {
    const time_used = timevalToUsec(timevalDiff(end.utime, start.utime));
    const mem_used: u64 = @intCast((end.maxrss - start.maxrss) * 1024);
    const mem_required: u64 = n * @sizeOf(Node);
    const overhead = if (mem_used > 0)
        (@as(f64, @floatFromInt(mem_used)) - @as(f64, @floatFromInt(@min(mem_required, mem_used)))) * 100.0 / @as(f64, @floatFromInt(mem_used))
    else
        0.0;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print("Time used:       {} usec\n", .{time_used});
    try stdout_writer.print("Memory used:     {} bytes\n", .{mem_used});
    try stdout_writer.print("Memory required: {} bytes\n", .{mem_required});
    try stdout_writer.print("Overhead:        {d:.1}%\n", .{overhead});

    try stdout_writer.flush(); // Don't forget to flush!
}
