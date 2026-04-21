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
#include <format>
#include <string_view>

namespace ds {

class DumbString {
public:
  DumbString() noexcept = default;
  DumbString(const char *s);
  DumbString(std::string_view s);

  DumbString(const DumbString &other) noexcept;
  DumbString(DumbString &&other) noexcept;

  ~DumbString();

  DumbString &operator=(const DumbString &other) noexcept;
  DumbString &operator=(DumbString &&other) noexcept;
  DumbString &operator=(const char *s);
  DumbString &operator=(std::string_view s);

  [[nodiscard]] const char *c_str() const noexcept;
  [[nodiscard]] std::string_view view() const noexcept;
  [[nodiscard]] bool unique() const noexcept;
  [[nodiscard]] bool empty() const noexcept;

  friend void swap(DumbString &a, DumbString &b) noexcept;

  friend std::strong_ordering operator<=>(const DumbString &a,
                                          const DumbString &b) noexcept;
  friend bool operator==(const DumbString &a, const DumbString &b) noexcept;

private:
  static constexpr std::uintptr_t UNIQUE_BIT = 1u;
  static constexpr std::uintptr_t PTR_MASK = ~UNIQUE_BIT;

  mutable std::uintptr_t raw_ = UNIQUE_BIT;

  static char *ptr_of(std::uintptr_t r) noexcept;
  static std::uintptr_t pack(char *p, bool uniq) noexcept;

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
    switch (m) {
    case mode::value_only:
      return std::format_to(ctx.out(), "{}", s.c_str());
    case mode::bit_only:
      return std::format_to(ctx.out(), "{}", bit);
    case mode::full:
      break;
    }
    return std::format_to(ctx.out(), "[{}]\"{}\"", bit, s.c_str());
  }
};
