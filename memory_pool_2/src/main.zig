const std = @import("std");
const Io = std.Io;

const memory_pool = @import("memory_pool");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.debug.print("Usage: {s} <allocator>\n", .{args[0]});
        std.debug.print("Available allocators:\n", .{});
        std.debug.print("    c LockedPoolAllocator LockFreePoolAllocator PoolAllocator\n", .{});
        return error.InvalidArguments;
    }
    const allocator_arg = args[1];

    const io = init.io;

    // Install the SIGSEGV handler before any pool is created
    memory_pool.pool_registry.installHandler();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    if (std.mem.eql(u8, allocator_arg, "c")) {
        try stdout_writer.print("\n========== C ALLOCATOR BENCHMARK ==========\n", .{});
        try stdout_writer.flush();
        try memory_pool.benchmarkHeap(io);
    } else if (std.mem.eql(u8, allocator_arg, "LockedPoolAllocator")) {
        try stdout_writer.print("\n========== LOCKED POOL ALLOCATOR BENCHMARK ==========\n", .{});
        try stdout_writer.flush();
        try memory_pool.benchmarkLockedPool(io);
    } else if (std.mem.eql(u8, allocator_arg, "LockFreePoolAllocator")) {
        try stdout_writer.print("\n========== LOCK-FREE POOL ALLOCATOR BENCHMARK ==========\n", .{});
        try stdout_writer.flush();
        try memory_pool.benchmarkLockFreePool(io);
    } else if (std.mem.eql(u8, allocator_arg, "PoolAllocator")) {
        try stdout_writer.print("\n========== THREAD-LOCAL POOL ALLOCATOR BENCHMARK ==========\n", .{});
        try stdout_writer.flush();
        try memory_pool.benchmarkLocalPool(io);
    } else if (std.mem.eql(u8, allocator_arg, "overflow")) {
        try stdout_writer.print("\n========== GUARD PAGE TEST ==========\n", .{});
        try stdout_writer.flush();
        memory_pool.benchmarkOverflow(io);
    } else {
        std.debug.print("Unknown allocator: {s}\n", .{allocator_arg});
        std.debug.print("Available allocators:\n", .{});
        std.debug.print("    c LockedPoolAllocator LockFreePoolAllocator PoolAllocator\n", .{});
        return error.InvalidArguments;
    }

    try stdout_writer.flush();
}
