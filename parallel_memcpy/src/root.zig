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

    for (0..workers) |i| {
        const offset = i * chunk_size;
        try group.concurrent(io, memcpyWorker, .{ dest[offset .. offset + chunk_size], src[offset .. offset + chunk_size] });
    }

    // Copy remaining bytes
    const remaining = src.len % chunk_size;
    if (remaining > 0) {
        const offset = workers * chunk_size;
        @memcpy(dest[offset .. offset + remaining], src[offset .. offset + remaining]);
    }

    try group.await(io);

    return dest;
}

pub fn memcpyWorker(noalias dest: []u8, noalias src: []const u8) Cancelable!void {
    @memcpy(dest, src);
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
