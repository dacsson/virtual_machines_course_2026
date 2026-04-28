# Memory pool 

## Usage 

Check if you have zig installed:
```
=>  zig version
0.16.0-dev.3028+a85495ca2
```

Then build and run:
```
=> zig build

=> ./zig-out/bin/memory_pool c

========== C ALLOCATOR BENCHMARK ==========
Time used: 797775 usec
Memory used: 319946752 bytes
Memory required: 160000000 bytes
Overhead: 49.99%

=> ./zig-out/bin/memory_pool pool

========== POOL ALLOCATOR BENCHMARK ==========
Time used: 475234 usec
Memory used: 160038912 bytes
Memory required: 160000000 bytes
Overhead: 0.02%
```

### Guard page overflow test

The `overflow` argument creates a pool too small for 10M nodes, triggering the guard page:
```
=> ./zig-out/bin/memory_pool overflow

========== GUARD PAGE TEST ==========
Memory pool overflow: write hit the guard page
```
The process terminates and signal handler prints diagnostic msg

## Project structure

```
.
├── build.zig        <- build script
├── build.zig.zon    <- dependencies
├── doc
│   ├── test.cc      <- cpp ver. from upstream
│   └── TASK.md      <- task description
├── README.md       
└── src
    ├── becnhmark.zig<- benchmark functions for lined list
    ├── main.zig     
    ├── pool.zig     <- memory pool impl.
    └── root.zig     <- exposes pool.zig API to main
```
