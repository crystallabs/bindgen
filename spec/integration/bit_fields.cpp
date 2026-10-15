/* Note: Used by `bit_fields_spec.cr` and `bit_fields_inline_spec.cr`. */

#include <stdint.h>

/// Settings packed into bit-fields.
struct Flags {
  unsigned narrow : 3; ///< Three bits.
  int wide : 12;
  bool on : 1;
  signed char tiny : 3; // Packed into the unit of `unsigned`.
  unsigned : 0;         // Moves `next` to the next unit.
  unsigned next : 5;
  int value;
  int64_t big : 40;
  int64_t negative : 20;
};

// A structure with constant bit-fields, which have no setter.
struct Constants {
  const unsigned fixed : 4;
  unsigned free : 4;
};

// A copied structure with a wrapper class.
struct Hosted {
  unsigned low : 4;
  unsigned high : 4;
};

// A union, in which each bit-field has its own storage.
union Variant {
  unsigned low : 4;
  int wide : 20;
  uint8_t byte;
};

// Zero-width bit-fields move the members after them, which needs padding.
struct ZeroWidth {
  char a;
  uint64_t : 0; // Moves `bits` to the next `uint64_t` unit.
  unsigned bits : 3;
  int d;
  char b;
  unsigned : 0; // Moves `e` to the next `unsigned` unit.
  char e;
};

// Bit-fields of an anonymous type.  C++ functions can't name it, so only
// `bit_fields_inline.yml` copies it.
struct AnonymousMember {
  struct {
    unsigned bits : 3;
  } member;
};

int anonymous_bits(AnonymousMember value) {
  return value.member.bits;
}

// Reads the bit-fields in C++, to compare with what Crystal wrote.
int64_t flags_sum(Flags flags) {
  return flags.narrow + flags.wide + flags.on + flags.tiny + flags.next +
    flags.value + flags.big + flags.negative;
}

// Writes the bit-fields in C++, for Crystal to read.
Flags flags_make() {
  Flags flags;
  flags.narrow = 5;
  flags.wide = -1000;
  flags.on = true;
  flags.tiny = -3;
  flags.next = 17;
  flags.value = 99;
  flags.big = -100000000000;
  flags.negative = -2;
  return flags;
}

Variant variant_make() {
  Variant variant;
  variant.wide = -5;
  return variant;
}

int variant_sum(Variant variant) {
  return variant.low;
}

ZeroWidth zero_width_make() {
  ZeroWidth value;
  value.a = 1;
  value.b = 2;
  value.bits = 5;
  value.d = 7;
  value.e = 3;
  return value;
}

int zero_width_sum(ZeroWidth value) {
  return value.a + value.b + value.bits + value.d + value.e;
}

Constants constants_make() {
  return Constants { 9, 3 };
}

Hosted hosted_make() {
  return Hosted { 7, 2 };
}
