# dumbstring

Single-bit reference-counted string smart pointers

## Build

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

Debug builds enable `DUMBSTRING_TRACE`, which logs frees to stderr

## Test

```bash
cd build && ctest
```

## Usage

```cpp
#include "dumbstring.hpp"
using ds::DumbString;

DumbString a("hello");          // unique
DumbString b(a);                // both shared now
DumbString c(std::move(a));     // c is shared, a is empty

std::cout << std::format("{}", b);   // [S]"hello"
std::cout << std::format("{:v}", b); // hello
std::cout << std::format("{:b}", b); // S
```
