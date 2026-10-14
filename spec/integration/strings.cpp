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
