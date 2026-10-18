// Deprecated methods are dropped overload by overload with
// `ignore_deprecated: true`, unlike `ignore_methods`, which drops a name.
class Api {
public:
  int fresh() { return 1; }

  [[deprecated("use fresh")]] int stale() { return 2; }

  int value(int a) { return a; }
  [[deprecated]] int value(int a, int b) { return a + b; }

  static int count() { return 3; }
  [[deprecated]] static int old_count() { return 4; }
};

int helper() { return 5; }
[[deprecated]] int old_helper() { return 6; }
