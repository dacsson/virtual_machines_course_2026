const std = @import("std");
const Io = std.Io;

const parallel_memcpy = @import("parallel_memcpy");

/// Benchmarks parallel memcpy performance with 256M of data.
fn benchmarkMemcpy(io: Io) !void {
    const size = 256 * 1024 * 1024;
    const allocator = std.heap.page_allocator;
    var prng: std.Random.DefaultPrng = .init(undefined);
    const rand = prng.random();
    const workers = [_]usize{ 0, 2, 4, 6, 8 };

    // Create a thread pool and group for parallel memcpy
    var pool: std.Io.Threaded = .init(allocator, .{ .concurrent_limit = Io.Limit.limited(8 + 1) });
    defer pool.deinit();
    const threaded_io = pool.io();
    var group: std.Io.Group = .init;

    const src = try allocator.alloc(u8, size);

    // Fill src with random data
    for (src) |*byte| {
        byte.* = rand.int(u8);
    }

    // Fresh allocation each time
    {
        const dst = try allocator.alloc(u8, size);
        defer allocator.free(dst);
        var timer = std.Io.Clock.awake.now(io);
        _ = @memcpy(dst, src);
        const elapsed = timer.untilNow(io, .awake);
        try printStats(io, "Standard memcpy", 0, elapsed);
    }

    for (workers) |worker| {
        const dst = try allocator.alloc(u8, size);
        defer allocator.free(dst);
        var timer = std.Io.Clock.awake.now(io);
        _ = try parallel_memcpy.memcpy(dst, src, worker, &group, threaded_io);
        const elapsed = timer.untilNow(io, .awake);
        try printStats(io, "Parallel memcpy", worker, elapsed);
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    try benchmarkMemcpy(io);
}

fn printStats(io: std.Io, msg: []const u8, workers: usize, elapsed: std.Io.Duration) !void {
    const time_used = elapsed.toNanoseconds();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print("{s} (workers = {d}): Time used: {} ns\n", .{ msg, workers, time_used });

    try stdout_writer.flush(); // Don't forget to flush!
}
