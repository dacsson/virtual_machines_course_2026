#include "dumbstring.hpp"

#include <cstring>
#include <new>
#include <print>
#include <utility>

namespace ds {

char *DumbString::ptr_of(std::uintptr_t r) noexcept {
  return reinterpret_cast<char *>(r & PTR_MASK);
}

std::uintptr_t DumbString::pack(char *p, bool uniq) noexcept {
  auto r = reinterpret_cast<std::uintptr_t>(p);
  return uniq ? (r | UNIQUE_BIT) : r;
}

DumbString::DumbString(const char *s) {
  if (s)
    alloc_(s, std::strlen(s));
}

DumbString::DumbString(std::string_view s) { alloc_(s.data(), s.size()); }

DumbString::DumbString(const DumbString &other) noexcept {
  char *p = ptr_of(other.raw_);
  if (!p)
    return;
  raw_ = reinterpret_cast<std::uintptr_t>(p); // ptr, U=0
  other.raw_ = raw_;                           // source also U=0
}

DumbString::DumbString(DumbString &&other) noexcept {
  raw_ = other.raw_;
  other.raw_ = UNIQUE_BIT;
}

DumbString::~DumbString() { release_(); }

DumbString &DumbString::operator=(const DumbString &other) noexcept {
  if (this == &other)
    return *this;
  release_();
  char *p = ptr_of(other.raw_);
  if (!p)
    return *this;
  raw_ = reinterpret_cast<std::uintptr_t>(p);
  other.raw_ = raw_;
  return *this;
}

DumbString &DumbString::operator=(DumbString &&other) noexcept {
  if (this == &other)
    return *this;
  release_();
  raw_ = other.raw_;
  other.raw_ = UNIQUE_BIT;
  return *this;
}

DumbString &DumbString::operator=(const char *s) {
  release_();
  if (s)
    alloc_(s, std::strlen(s));
  return *this;
}

DumbString &DumbString::operator=(std::string_view s) {
  release_();
  alloc_(s.data(), s.size());
  return *this;
}

const char *DumbString::c_str() const noexcept {
  char *p = ptr_of(raw_);
  return p ? p : "";
}

std::string_view DumbString::view() const noexcept {
  char *p = ptr_of(raw_);
  return p ? std::string_view(p) : std::string_view{};
}

bool DumbString::unique() const noexcept { return (raw_ & UNIQUE_BIT) != 0; }

bool DumbString::empty() const noexcept { return ptr_of(raw_) == nullptr; }

void swap(DumbString &a, DumbString &b) noexcept {
  if (&a == &b)
    return;
  DumbString tmp(std::move(a));
  a = std::move(b);
  b = std::move(tmp);
}

std::strong_ordering operator<=>(const DumbString &a,
                                 const DumbString &b) noexcept {
  const int c = std::strcmp(a.c_str(), b.c_str());
  if (c < 0)
    return std::strong_ordering::less;
  if (c > 0)
    return std::strong_ordering::greater;
  return std::strong_ordering::equal;
}

bool operator==(const DumbString &a, const DumbString &b) noexcept {
  return std::strcmp(a.c_str(), b.c_str()) == 0;
}

void DumbString::alloc_(const char *s, std::size_t n) {
  // explicitly requesting alignof(void*) 
  // guarantees the returned address is at least 2-byte aligned
  // => bit 0 is always free for us to use as the tag
  constexpr std::align_val_t kAlign{alignof(void *)};
  void *mem = ::operator new[](n + 1, kAlign);
  char *buf = static_cast<char *>(mem);
  std::memcpy(buf, s, n);
  buf[n] = '\0';
  raw_ = pack(buf, true);
}

void DumbString::release_() noexcept {
  char *p = ptr_of(raw_);
  if (p && unique()) {
#ifdef DUMBSTRING_TRACE
    std::println(stderr, "[dumbstring] free \"{}\"", p);
#endif
    // explicitly requesting alignof(void*) 
    // guarantees the returned address is at least 2-byte aligned
    // => bit 0 is always free for us to use as the tag
    constexpr std::align_val_t kAlign{alignof(void *)};
    ::operator delete[](p, kAlign);
  }
  raw_ = UNIQUE_BIT;
}

} // namespace ds
