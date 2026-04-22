#include "dumbstring.hpp"

#include <cassert>
#include <cstring>
#include <format>
#include <print>

using ds::DumbString;

static void test_default() {
  DumbString s;
  assert(s.empty());
  assert(s.c_str() == nullptr);
}

static void test_from_literal() {
  DumbString s("hello");
  assert(s.unique());
  assert(!s.empty());
  assert(std::strcmp(s.c_str(), "hello") == 0);
}

static void test_copy_shares() {
  DumbString a("world");
  assert(a.unique());
  DumbString b(a);
  assert(!a.unique());
  assert(!b.unique());
  assert(std::strcmp(b.c_str(), "world") == 0);
}

static void test_string_assign() {
  DumbString a("one");
  DumbString b(a);
  assert(!a.unique());
  a = "two";
  assert(a.unique());
  assert(std::strcmp(a.c_str(), "two") == 0);
  assert(!b.unique()); // b stays shared forever
  assert(std::strcmp(b.c_str(), "one") == 0);
}

static void test_smart_assign() {
  DumbString a("first");
  DumbString b("second");
  a = b;
  assert(!a.unique() && !b.unique());
  assert(std::strcmp(a.c_str(), "second") == 0);
}

static void test_self_assign() {
  DumbString a("same");
  DumbString b(a);
  a = a;
  assert(!a.unique());
  assert(std::strcmp(a.c_str(), "same") == 0);
}

static void test_move() {
  DumbString a("moved");
  DumbString b(std::move(a));
  assert(b.unique());
  assert(std::strcmp(b.c_str(), "moved") == 0);
  assert(a.empty());
}

static void test_print() {
  DumbString a("hi");
  assert(std::format("{}", a) == "[U]\"hi\"");

  DumbString b(a);
  assert(std::format("{}", a) == "[S]\"hi\"");
}

static void test_compare() {
  DumbString a("apple");
  DumbString b("banana");
  assert(a < b);
  assert(a != b);
  DumbString c("apple");
  assert(a == c);
}

static void test_format() {
  DumbString a("hi");
  assert(std::format("{}", a) == "[U]\"hi\"");
  assert(std::format("{:f}", a) == "[U]\"hi\"");
  assert(std::format("{:v}", a) == "hi");
  assert(std::format("{:b}", a) == "U");

  DumbString b(a);
  assert(std::format("{}", a) == "[S]\"hi\"");
  assert(std::format("{:b}", b) == "S");
  assert(std::format("{:v}", b) == "hi");

  assert(std::format("{} < {}", DumbString("a"), DumbString("b")) ==
         "[U]\"a\" < [U]\"b\"");
}

int main() {
  test_default();
  test_from_literal();
  test_copy_shares();
  test_string_assign();
  test_smart_assign();
  test_self_assign();
  test_move();
  test_print();
  test_compare();
  test_format();
  std::println("test_basic: OK");
  return 0;
}
