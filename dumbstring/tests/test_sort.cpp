#include "dumbstring.hpp"

#include <cassert>
#include <cstddef>
#include <cstring>
#include <print>
#include <utility>

using ds::DumbString;

static void bubble_sort(DumbString *a, std::size_t n) {
  using std::swap;
  for (std::size_t i = 0; i + 1 < n; ++i)
    for (std::size_t j = 0; j + 1 < n - i; ++j)
      if (a[j + 1] < a[j])
        swap(a[j], a[j + 1]);
}

static void test_sort_all_unique() {
  DumbString a[5] = {DumbString("delta"), DumbString("bravo"),
                     DumbString("echo"), DumbString("alpha"),
                     DumbString("charlie")};
  for (const auto &s : a)
    assert(s.unique());

  bubble_sort(a, 5);

  const char *expected[] = {"alpha", "bravo", "charlie", "delta", "echo"};
  for (std::size_t i = 0; i < 5; ++i) {
    assert(std::strcmp(a[i].c_str(), expected[i]) == 0);
    assert(a[i].unique());
  }
}

static void test_sort_preserves_shared_bit() {
  DumbString a[5] = {DumbString("delta"), DumbString("bravo"),
                     DumbString("echo"), DumbString("alpha"),
                     DumbString("charlie")};
  DumbString external = a[1];
  assert(!a[1].unique());
  assert(!external.unique());
  assert(std::strcmp(external.c_str(), "bravo") == 0);
  for (std::size_t i : {0u, 2u, 3u, 4u})
    assert(a[i].unique());

  bubble_sort(a, 5);

  const char *expected[] = {"alpha", "bravo", "charlie", "delta", "echo"};
  for (std::size_t i = 0; i < 5; ++i)
    assert(std::strcmp(a[i].c_str(), expected[i]) == 0);

  // "bravo" element must still be shared (external holds a copy)
  assert(!a[1].unique());
  assert(!external.unique());
  assert(std::strcmp(external.c_str(), "bravo") == 0);

  // all others stay unique
  for (std::size_t i : {0u, 2u, 3u, 4u})
    assert(a[i].unique());
}

static void test_sort_with_external_coowner() {
  DumbString a[3] = {DumbString("gamma"), DumbString("alpha"),
                     DumbString("beta")};
  DumbString external = a[0];
  assert(!a[0].unique() && !external.unique());

  bubble_sort(a, 3);

  const char *expected[] = {"alpha", "beta", "gamma"};
  for (std::size_t i = 0; i < 3; ++i)
    assert(std::strcmp(a[i].c_str(), expected[i]) == 0);

  // "gamma" moved to a[2], still shared with external
  assert(!a[2].unique());
  assert(!external.unique());
  assert(std::strcmp(external.c_str(), "gamma") == 0);
  assert(a[0].unique() && a[1].unique());
}

static void test_sort_already_sorted() {
  DumbString a[4] = {DumbString("a"), DumbString("b"), DumbString("c"),
                     DumbString("d")};
  DumbString x = a[2];
  DumbString y = a[2];
  assert(!a[2].unique() && !x.unique() && !y.unique());

  bubble_sort(a, 4);

  const char *expected[] = {"a", "b", "c", "d"};
  for (std::size_t i = 0; i < 4; ++i)
    assert(std::strcmp(a[i].c_str(), expected[i]) == 0);

  assert(a[0].unique() && a[1].unique() && a[3].unique());
  assert(!a[2].unique() && !x.unique() && !y.unique());
  assert(std::strcmp(x.c_str(), "c") == 0);
  assert(std::strcmp(y.c_str(), "c") == 0);
}

int main() {
  test_sort_all_unique();
  test_sort_preserves_shared_bit();
  test_sort_with_external_coowner();
  test_sort_already_sorted();
  std::println("test_sort: OK");
  return 0;
}
