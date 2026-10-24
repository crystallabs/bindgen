#include <string>

/* Out arguments of built-in types, with `builtin_out_arguments: true`: every
 * non-const reference or pointer to a built-in type or an enum a method writes
 * through is one, in every method, except a pointer to a byte or character
 * type, or to `void`, a buffer.  An `out_arguments` entry of the class decides
 * instead.  See `Parser::Method#out_arguments`. */

enum class Unit { Meters, Feet };

class Numbers {
public:
  // An out pointer defaulting to `nullptr`, like `QString::toInt(bool *ok)`:
  // `{Int32, Bool}`, the wrapper drops the argument.
  int toInt(bool *ok = nullptr, int base = 10) const {
    if (ok) *ok = base == 10;
    return base * 4;
  }

  // Several out pointers, void: `{Int32, Int32, Int32}`.
  void getDate(int *year, int *month, int *day) const {
    *year = 2026;
    *month = 10;
    *day = 24;
  }

  // An in/out reference: the wrapper takes and returns the value.
  void bump(int &value) const {
    value += 1;
  }

  // An enum out pointer.
  double convert(double value, Unit *unit) const {
    *unit = Unit::Feet;
    return value * 3;
  }

  // Buffers stay pointers: bytes, characters and void.
  int read(char *buffer, int max) const {
    for (int i = 0; i < max; ++i) buffer[i] = static_cast<char>('a' + i);
    return max;
  }

  void fill(unsigned char *data, int count) const {
    for (int i = 0; i < count; ++i) data[i] = 1;
  }

  void raw(void *data) const {
    *static_cast<int *>(data) = 5;
  }

  // `out_arguments: false`: stays a pointer, it's an array.
  void copyTo(float *values) const {
    values[0] = 1.5f;
    values[1] = 2.5f;
  }

  // `out_arguments: true`: a byte out argument after all.
  int readByte(char *out) const {
    *out = 'b';
    return 1;
  }

  // `out_arguments: [1]`: only the second pointer is out.
  void two(int *a, int *b) const {
    *a += 1;
    *b = 2;
  }
};

// A virtual method with a built-in out argument: the override returns the
// tuple, which is written back through the pointer.
class Measurer {
public:
  virtual ~Measurer() { }

  virtual bool measure(int *width) const {
    *width = 10;
    return true;
  }

  std::string run() const {
    int width = 0;
    bool ok = measure(&width);
    return (ok ? "ok " : "no ") + std::to_string(width);
  }
};

// Inherits the `out_arguments` entry of its base for the override.
class Ruler : public Measurer {
public:
  bool measure(int *width) const override {
    *width = 30;
    return true;
  }
};
