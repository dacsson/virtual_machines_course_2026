const std = @import("std");
const Io = std.Io;
const PoolpFictionAllocator = @import("pool.zig");

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

const Node = struct {
    /// Nullable ptr to next node in list
    next: ?*Node,
    id: usize,

    pub fn init(id: usize) Node {
        return Node{
            .next = null,
            .id = id,
        };
    }
};

fn createListHeap(allocator: std.mem.Allocator, n: usize) !?*Node {
    var list: ?*Node = null;
    for (0..n) |i| {
        const node = try allocator.create(Node);
        node.* = Node.init(i);
        node.next = list;
        list = node;
    }
    return list;
}

fn deleteList(allocator: std.mem.Allocator, list: ?*Node) void {
    var current = list;
    while (current) |node| {
        current = node.next;
        allocator.destroy(node);
    }
}

fn createListPool(pool: *PoolpFictionAllocator, n: usize) ?*Node {
    var list: ?*Node = null;
    for (0..n) |i| {
        const node = pool.bump(Node);
        node.* = Node.init(i);
        node.next = list;
        list = node;
    }
    return list;
}

pub fn benchmarkPool(io: std.Io, n: usize, pool_size: usize) !void {
    const start = std.posix.getrusage(std.posix.rusage.SELF);

    var pool = PoolpFictionAllocator.init(pool_size) catch return error.OutOfMemory;
    _ = createListPool(&pool, n);
    pool.destroyPool();

    const end = std.posix.getrusage(std.posix.rusage.SELF);
    try printStats(io, start, end, n);
}

pub fn benchmarkHeap(allocator: std.mem.Allocator, io: std.Io, n: usize) !void {
    const start = std.posix.getrusage(std.posix.rusage.SELF);

    const list = try createListHeap(allocator, n);
    deleteList(allocator, list);

    const end = std.posix.getrusage(std.posix.rusage.SELF);
    try printStats(io, start, end, n);
}

fn printStats(io: std.Io, start: std.posix.rusage, end: std.posix.rusage, n: usize) !void {
    const time_used = timevalToUsec(timevalDiff(end.utime, start.utime));
    const mem_used: u64 = @intCast((end.maxrss - start.maxrss) * 1024);
    const mem_required: u64 = n * @sizeOf(Node);
    const overhead = @as(f64, @as(f64, @floatFromInt(mem_used)) - @as(f64, @floatFromInt(mem_required))) * 100.0 / @as(f64, @floatFromInt(mem_used));

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print("Time used: {} usec\n", .{time_used});
    try stdout_writer.print("Memory used: {} bytes\n", .{mem_used});
    try stdout_writer.print("Memory required: {} bytes\n", .{mem_required});
    try stdout_writer.print("Overhead: {d:.2}%\n", .{overhead});

    try stdout_writer.flush(); // Don't forget to flush!
}
