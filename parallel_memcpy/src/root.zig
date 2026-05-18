const std = @import("std");
const Io = std.Io;
const Thread = std.Io.Threaded;
const Cancelable = std.Io.Cancelable;
const Mutex = std.Io.Mutex;

pub fn memcpy(noalias dest: []u8, noalias src: []const u8, workers: usize, group: *std.Io.Group, io: Io) ![]u8 {
    if (workers == 0) {
        @memcpy(dest, src);
        return dest;
    }

    errdefer group.cancel(io);

    const chunk_size = src.len / workers;

    // var stdout_buffer: [1024]u8 = undefined;
    // var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    // const stdout_writer = &stdout_file_writer.interface;

    // try stdout_writer.print("memcpy: src={any} dest={any}\n", .{ src, dest });

    for (0..workers) |i| {
        const offset = i * chunk_size;
        try group.concurrent(io, memcpyWorker, .{ dest[offset .. offset + chunk_size], src[offset .. offset + chunk_size] });
        // try stdout_writer.print("Hi from worker {}\n", .{i});
        // try stdout_writer.flush();
    }

    // Copy remaining bytes
    const remaining = src.len % chunk_size;
    if (remaining > 0) {
        const offset = workers * chunk_size;
        try group.concurrent(io, memcpyWorker, .{ dest[offset .. offset + remaining], src[offset .. offset + remaining] });
    }

    try group.await(io);

    return dest;
}

pub fn memcpyWorker(noalias dest: []u8, noalias src: []const u8) Cancelable!void {
    @memcpy(dest, src);

    // var stdout_buffer: [1024]u8 = undefined;
    // var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    // const stdout_writer = &stdout_file_writer.interface;

    // stdout_writer.print("Hi! I am {} doing a memcpy on {any}->{any}\n", .{ worker_id, src, dest }) catch return error.Canceled;
    // stdout_writer.flush() catch return error.Canceled;
}

test "memory is equal after memcpy" {
    var array = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var zeroed = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

    const allocator = std.heap.page_allocator;
    var pool: std.Io.Threaded = .init(allocator, .{ .concurrent_limit = Io.Limit.limited(8 + 1) });
    defer pool.deinit();

    const io = pool.io();

    var group: std.Io.Group = .init;

    const result = try memcpy(zeroed[0..], array[0..], 8, &group, io);
    for (0..10) |i| {
        try std.testing.expectEqual(zeroed[i], result[i]);
    }
}
