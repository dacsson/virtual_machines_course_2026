const std = @import("std");
const Io = std.Io;

const memory_pool = @import("memory_pool");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.debug.print("Usage: {s} [c|pool|overflow]\n", .{args[0]});
        return error.InvalidArguments;
    }
    const allocator_arg = args[1];

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    if (std.mem.eql(u8, allocator_arg, "c")) {
        try stdout_writer.print("\n========== C ALLOCATOR BENCHMARK ==========\n", .{});
        try stdout_writer.flush();

        try memory_pool.benchmarkHeap(std.heap.c_allocator, io, 10_000_000);
    } else if (std.mem.eql(u8, allocator_arg, "pool")) {
        try stdout_writer.print("\n========== POOL ALLOCATOR BENCHMARK ==========\n", .{});
        try stdout_writer.flush();

        try memory_pool.benchmarkPool(io, 10_000_000, 10_000_000 * 16 + std.heap.pageSize());
    } else if (std.mem.eql(u8, allocator_arg, "overflow")) {
        try stdout_writer.print("\n========== GUARD PAGE TEST ==========\n", .{});
        try stdout_writer.flush();

        try memory_pool.benchmarkPool(io, 10_000_000, std.heap.pageSize());
    }

    try stdout_writer.flush();
}
