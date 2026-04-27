const std = @import("std");
const Io = std.Io;

const memory_pool = @import("memory_pool");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.debug.print("Usage: {s} [heap|pool]\n", .{args[0]});
        return error.InvalidArguments;
    }
    const allocator_arg = args[1];

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    if (std.mem.eql(u8, allocator_arg, "c")) {
        try stdout_writer.print("\n========== C ALLOCATOR BENCHMARK ==========\n", .{});

        const default_allocator = std.heap.c_allocator;
        try memory_pool.benchmarkDefaultList(default_allocator, io, 10000000, null);
    } else if (std.mem.eql(u8, allocator_arg, "pool")) {
        try stdout_writer.print("\n========== POOL ALLOCATOR BENCHMARK ==========\n", .{});

        // allocator arg is unused for pool path, pool is created inside the benchmark
        try memory_pool.benchmarkDefaultList(undefined, io, 10000000, 10000000 * 16 + std.heap.pageSize());
    }

    try stdout_writer.flush();
}
