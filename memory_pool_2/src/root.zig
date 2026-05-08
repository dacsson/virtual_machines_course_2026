const benchmark = @import("benchmark.zig");
pub const benchmarkHeap = benchmark.benchmarkHeap;
pub const benchmarkLockedPool = benchmark.benchmarkLockedPool;
pub const benchmarkLockFreePool = benchmark.benchmarkLockFreePool;
pub const benchmarkLocalPool = benchmark.benchmarkLocalPool;
pub const benchmarkOverflow = benchmark.benchmarkOverflow;

pub const PoolpFictionAllocator = @import("pool.zig");
pub const LockedPoolAllocator = @import("locked_pool.zig");
pub const LockFreePoolAllocator = @import("lockfree_pool.zig");
pub const pool_registry = @import("pool_registry.zig");
