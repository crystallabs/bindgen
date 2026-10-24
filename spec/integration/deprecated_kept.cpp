// The classes of deprecated.cpp, with `ignore_deprecated` off: the deprecated
// methods are kept under `@[Deprecated]`.  Also the global `ignore_methods`.
#include "deprecated.cpp"

struct Noisy {
  int keep() { return 1; }
  int drop() { return 2; }
  int dropOne(int a) { return a; }
  int dropOne(double a) { return static_cast<int>(a) * 10; }
  int dropByRegex() { return 3; }
};

struct Quiet {
  int drop() { return 4; }
};
