# Non-blocking memory pool 

## Usage 

Check if you have zig installed:
```
=>  zig version
0.17.0-dev.263+0add2dfc4
```

Then build and run:
```
=> zig build run -- <allocator>
```

Available allocators: `c`, `LockedPoolAllocator`, `LockFreePoolAllocator`, `PoolAllocator`, `overflow`

## Benchmark results

16 threads, 10M nodes per thread (160M total), Node = 16 bytes

```
=> zig build run -- c

========== C ALLOCATOR BENCHMARK ==========
Time used:       21261996 usec
Memory used:     4317265920 bytes
Memory required: 2560000000 bytes
Overhead:        40.7%

=> zig build run -- LockedPoolAllocator

========== LOCKED POOL ALLOCATOR BENCHMARK ==========
Time used:       26735319 usec
Memory used:     2562666496 bytes
Memory required: 2560000000 bytes
Overhead:        0.1%

=> zig build run -- LockFreePoolAllocator

========== LOCK-FREE POOL ALLOCATOR BENCHMARK ==========
Time used:       40782555 usec
Memory used:     2562449408 bytes
Memory required: 2560000000 bytes
Overhead:        0.1%

=> zig build run -- PoolAllocator

========== THREAD-LOCAL POOL ALLOCATOR BENCHMARK ==========
Time used:       197449 usec
Memory used:     2206109696 bytes
Memory required: 2560000000 bytes
Overhead:        0.0%
```

### Guard page overflow test

The `overflow` argument creates a pool too small for 10M nodes, triggering the guard page:
```
=> zig build run -- overflow

========== GUARD PAGE TEST ==========
Bad alloc in PoolAllocator: pool begins at 0x00007f76a5d6c000 
```
The SIGSEGV handler identifies which pool overflowed by its base address and exits with code 3.

## Project structure

```
.
├── build.zig            <- build script
├── build.zig.zon        <- dependencies
├── doc
│   ├── reference.cc     <- C++ reference implementation
│   └── TASK.md          <- task description
├── README.md            <- you are here
└── src
    ├── benchmark.zig    <- multi-threaded benchmark functions
    ├── locked_pool.zig  <- global pool under Io.Mutex
    ├── lockfree_pool.zig<- global non-blocking pool (atomic)
    ├── main.zig         <- CLI entry point
    ├── pool.zig         <- thread-local pool (PoolpFictionAllocator)
    ├── pool_registry.zig<- pool registry + SIGSEGV handler
    └── root.zig         <- exports module API
```
