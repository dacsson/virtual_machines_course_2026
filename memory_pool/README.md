# Memory pool 

## Usage 

Check if you have zig installed:
```
=>  zig version
0.16.0-dev.3028+a85495ca2
```

Then build and run:
```
=>  ./zig-out/bin/memory_pool c
Time used: 797775 usec
Memory used: 319946752 bytes
Memory required: 160000000 bytes
Overhead: 49.99%

========== C ALLOCATOR BENCHMARK ==========
=>  ./zig-out/bin/memory_pool pool
Time used: 475234 usec
Memory used: 160038912 bytes
Memory required: 160000000 bytes
Overhead: 0.02%

========== POOL ALLOCATOR BENCHMARK ==========
```

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
