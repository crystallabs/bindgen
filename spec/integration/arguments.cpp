#include <string>

enum Numeral {
  First,
  Second,
};

enum Bits : unsigned int {
  Nothing = 0,
  Everything = 0xffffffffu, // Above Int32::MAX
};

class Defaults {
public:
  int defaultEnum(Numeral n = Second) {
    return static_cast<int>(n);
  }

  int defaultInt32(int n = 123) {
    return n;
  }

  int defaultLargeEnum(Bits b = Everything) {
    return b == Everything ? 1 : 0;
  }

  void defaultTrue(bool n = true) { }
  void defaultFalse(bool n = false) { }

  int defaultString(std::string str = "Okay") {
    return str.length();
  }

  Defaults *nilable(Defaults *defaults = nullptr) {
    return defaults;
  }
};
