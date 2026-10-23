#include <string>

// Long enough to live on the heap instead of in the string object itself.
#define LONG_STRING "A string that is too long for the small string optimization"

static int stringCalls = 0;

std::string string_by_value() {
  stringCalls++;
  return LONG_STRING;
}

const std::string string_by_const_value() {
  return "btrfs";
}

int string_calls() {
  return stringCalls;
}

class Strings {
  std::string m_name;

public:
  Strings() : m_name(LONG_STRING) { }
  virtual ~Strings() { }

  std::string byValue() {
    stringCalls++;
    return "btrfs";
  }

  std::string longByValue() const {
    return m_name + "!";
  }

  const std::string &byReference() const {
    return m_name;
  }

  static std::string staticByValue() {
    return std::string(LONG_STRING) + "?";
  }

  std::string echo(std::string value) {
    return value;
  }

  // Overridden in Crystal, to pass a Crystal `String` back into C++.
  virtual std::string virtualName() {
    return "C++";
  }

  std::string callVirtualName() {
    return virtualName() + virtualName();
  }
};

// A view of a string, converted like `std::string` for a call: an overload
// taking the view next to one taking the string is dropped (`shadowed_by`).
struct View {
  const char *ptr;
  size_t size;

  View(const std::string &s) : ptr(s.data()), size(s.size()) { }
  View(const char *p, size_t n) : ptr(p), size(n) { }
};

struct Viewer {
  int count(const std::string &s) { return 1; }
  int count(View v) { return 2; } // Shadowed
  int count(View v, int times) { return 3 * times; } // Not shadowed: no `(std::string, int)`
  size_t viewOnly(View v) { return v.size; }
  std::string twice(View a, View b) { return std::string(a.ptr, a.size) + std::string(b.ptr, b.size); }
  std::string twice(const std::string &a, const std::string &b) { return a + "+" + b; }
  View peek() const { return View("peek", 4); }
};
