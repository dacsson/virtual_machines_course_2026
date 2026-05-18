# Whats this?

Parallel memcpy implementation

## Benchmarks

```
Standard memcpy (workers = 0): Time used: 30155529 ns
Parallel memcpy (workers = 0): Time used: 29976624 ns
Parallel memcpy (workers = 2): Time used: 29397592 ns
Parallel memcpy (workers = 4): Time used: 28283406 ns
Parallel memcpy (workers = 6): Time used: 25986810 ns
Parallel memcpy (workers = 8): Time used: 25481753 ns
```

## Test

Test for memory equality after parallel memcpy is in `src/root.zig`:
```
~/Uni/VirtualMachines/virtual_machines_course_2026/parallel_memcpy  =>  zig build test --summary all
Build Summary: 5/5 steps succeeded; 1/1 tests passed
test success
├─ run test 1 pass (1 total) 5ms MaxRSS:7M
│  └─ compile test Debug native cached 9ms MaxRSS:37M
└─ run test success 5ms MaxRSS:7M
   └─ compile test Debug native cached 10ms MaxRSS:37M
```

## Project structure

```
src/
├── main.zig <- benchmark runner 
├── root.zig <- memcpy implementation
```
