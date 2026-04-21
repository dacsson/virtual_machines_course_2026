cmake_minimum_required(VERSION 3.20)
project(dumbstring CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug)
endif()

add_library(dumbstring STATIC src/dumbstring.cpp)
target_include_directories(dumbstring PUBLIC include)
target_compile_options(dumbstring PRIVATE -Wall -Wextra -Wpedantic)
target_compile_definitions(dumbstring PUBLIC
    $<$<CONFIG:Debug>:DUMBSTRING_TRACE>)

enable_testing()

add_executable(test_basic tests/test_basic.cpp)
target_link_libraries(test_basic PRIVATE dumbstring)
target_compile_options(test_basic PRIVATE -Wall -Wextra -Wpedantic)
add_test(NAME basic COMMAND test_basic)

add_executable(test_sort tests/test_sort.cpp)
target_link_libraries(test_sort PRIVATE dumbstring)
target_compile_options(test_sort PRIVATE -Wall -Wextra -Wpedantic)
add_test(NAME sort COMMAND test_sort)
