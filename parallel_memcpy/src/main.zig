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
    const dst_for_parr = try allocator.alloc(u8, size);
    const dst_for_seq = try allocator.alloc(u8, size);

    // Fill src with random data
    for (src) |*byte| {
        byte.* = rand.int(u8);
    }

    // First run sequential memcpy
    var timer = std.Io.Clock.awake.now(io);
    _ = @memcpy(dst_for_seq, src);
    var elapsed = timer.untilNow(io, .awake);
    try printStats(io, "Standard memcpy", 0, elapsed);

    // Second run parallel memcpy for each worker size
    for (workers) |worker| {
        timer = std.Io.Clock.awake.now(io);
        _ = try parallel_memcpy.memcpy(dst_for_parr, src, worker, &group, threaded_io);
        elapsed = timer.untilNow(io, .awake);
        try printStats(io, "Parallel memcpy", worker, elapsed);
    }
}

pub fn main(init: std.process.Init) !void {
    // // Prints to stderr, unbuffered, ignoring potential errors.
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // This is appropriate for anything that lives as long as the process.
    // const arena: std.mem.Allocator = init.arena.allocator();

    // // Accessing command line arguments:
    // const args = try init.minimal.args.toSlice(arena);
    // for (args) |arg| {
    //     std.log.info("arg: {s}", .{arg});
    // }

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // // Stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // var stdout_buffer: [1024]u8 = undefined;
    // var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    // const stdout_writer = &stdout_file_writer.interface;

    // try parallel_memcpy.printAnotherMessage(stdout_writer);

    // try stdout_writer.flush(); // Don't forget to flush!
    // Each array is 256M
    // const workers = 8;
    // var src = try arena.alloc(u8, 10);
    // const dst = try arena.alloc(u8, 10);
    // for (0..10) |i| {
    //     src[i] = @intCast(i);
    // }
    // _ = try parallel_memcpy.memcpy(dst, src, workers);

    // for (0..10) |i| {
    //     std.debug.print("src[{d}] = {d}\n", .{ i, src[i] });
    // }
    // for (0..10) |i| {
    //     std.debug.print("dst[{d}] = {d}\n", .{ i, dst[i] });
    // }
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
