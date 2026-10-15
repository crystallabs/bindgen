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

Constants constants_make() {
  return Constants { 9, 3 };
}

Hosted hosted_make() {
  return Hosted { 7, 2 };
}
