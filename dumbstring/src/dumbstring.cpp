#include "dumbstring.hpp"

#include <cstring>
#include <print>

namespace ds {

DumbString::DumbString(const char *s) {
  if (s)
    alloc_(s, std::strlen(s));
}

DumbString::DumbString(std::string_view s) { alloc_(s.data(), s.size()); }

DumbString::~DumbString() { release_(); }

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

void DumbString::alloc_(const char *s, std::size_t n) {
  void *mem = ::operator new[](n + 1);
  char *buf = static_cast<char *>(mem);
  std::memcpy(buf, s, n);
  buf[n] = '\0';
  raw_ = pack(buf);
}

void DumbString::release_() noexcept {
  if (unique()) {
    char *p = ptr_of(raw_);
#ifdef DUMBSTRING_TRACE
    if (p)
      std::println(stderr, "[dumbstring] free \"{}\"", p);
#endif
    ::operator delete[](p);
  }
  raw_ = 0;
}

} // namespace ds
