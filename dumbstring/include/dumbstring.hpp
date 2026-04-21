#pragma once

// 1bit reference counting via a tagged pointer
//
//   raw_ - char ptr tagged with the uniqueness bit in LSB
//
// Rules:
//   - unique (U=1): destructor frees the buffer.
//   - shared (U=0): destructor does nothing (string leaks by design).
//   - copy: both sides become shared (U=0).
//   - move: raw_ transferred, source reset to empty.
//   - swap: move-triangle, so uniqueness bits travel with the data.

#include <compare>
#include <cstdint>
#include <cstring>
#include <format>
#include <string_view>

namespace ds {

class DumbString {
public:
  DumbString() noexcept = default;
  DumbString(const char *s);
  DumbString(std::string_view s);

  DumbString(const DumbString &other) noexcept
      : raw_{other.raw_ & PTR_MASK} {
    if (raw_)
      other.raw_ = raw_;
  }

  DumbString(DumbString &&other) noexcept : raw_{other.raw_} {
    other.raw_ = 0;
  }

  ~DumbString();

  DumbString &operator=(const DumbString &other) noexcept {
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

  DumbString &operator=(DumbString &&other) noexcept {
    if (this == &other)
      return *this;
    release_();
    raw_ = other.raw_;
    other.raw_ = 0;
    return *this;
  }

  DumbString &operator=(const char *s);
  DumbString &operator=(std::string_view s);

  [[nodiscard]] const char *c_str() const noexcept {
    return ptr_of(raw_);
  }

  [[nodiscard]] std::string_view view() const noexcept {
    char *p = ptr_of(raw_);
    return p ? std::string_view(p) : std::string_view{};
  }

  [[nodiscard]] bool unique() const noexcept {
    return empty() || (raw_ & UNIQUE_BIT) != 0;
  }

  [[nodiscard]] bool empty() const noexcept {
    return ptr_of(raw_) == nullptr;
  }

  friend std::strong_ordering operator<=>(const DumbString &a,
                                          const DumbString &b) noexcept {
    const char *pa = a.c_str(), *pb = b.c_str();
    if (!pa && !pb)
      return std::strong_ordering::equal;
    if (!pa)
      return std::strong_ordering::less;
    if (!pb)
      return std::strong_ordering::greater;
    const int c = std::strcmp(pa, pb);
    if (c < 0)
      return std::strong_ordering::less;
    if (c > 0)
      return std::strong_ordering::greater;
    return std::strong_ordering::equal;
  }

  friend bool operator==(const DumbString &a,
                          const DumbString &b) noexcept {
    const char *pa = a.c_str(), *pb = b.c_str();
    if (!pa || !pb)
      return pa == pb;
    return std::strcmp(pa, pb) == 0;
  }

private:
  static constexpr std::uintptr_t UNIQUE_BIT = 1u;
  static constexpr std::uintptr_t PTR_MASK = ~UNIQUE_BIT;

  mutable std::uintptr_t raw_ = 0;

  static char *ptr_of(std::uintptr_t r) noexcept {
    return reinterpret_cast<char *>(r & PTR_MASK);
  }

  static std::uintptr_t pack(char *p, bool uniq) noexcept {
    auto r = reinterpret_cast<std::uintptr_t>(p);
    return uniq ? (r | UNIQUE_BIT) : r;
  }

  void alloc_(const char *s, std::size_t n);
  void release_() noexcept;
};

} // namespace ds

template <> struct std::formatter<ds::DumbString> {
  enum class mode { full, value_only, bit_only };
  mode m = mode::full;

  constexpr auto parse(std::format_parse_context &ctx) {
    auto it = ctx.begin();
    if (it == ctx.end() || *it == '}')
      return it;
    switch (*it) {
    case 'v':
      m = mode::value_only;
      break;
    case 'b':
      m = mode::bit_only;
      break;
    case 'f':
      m = mode::full;
      break;
    default:
      throw std::format_error("DumbString: unknown format spec");
    }
    ++it;
    if (it != ctx.end() && *it != '}')
      throw std::format_error("DumbString: trailing chars in format spec");
    return it;
  }

  auto format(const ds::DumbString &s, std::format_context &ctx) const {
    const char bit = s.unique() ? 'U' : 'S';
    const char *p = s.c_str();
    const char *str = p ? p : "(null)";
    switch (m) {
    case mode::value_only:
      return std::format_to(ctx.out(), "{}", str);
    case mode::bit_only:
      return std::format_to(ctx.out(), "{}", bit);
    case mode::full:
      break;
    }
    return std::format_to(ctx.out(), "[{}]\"{}\"", bit, str);
  }
};
