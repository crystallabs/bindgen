int defaultFactor() { return 10; }

/// A documented class.
///
/// It has a second paragraph.
class Documented {
public:
  /// Builds a documented instance.
  Documented() : value(1) { }

  /** Adds *a* and *b* to the value.
   *  @param a The first summand. */
  int add(int a, int b = 2) { return value + a + b; }

  /// Multiplies *x*.  The default factor can't be copied into Crystal, so
  /// there's one overload with and one without it.
  int scale(int x, int factor = defaultFactor()) { return x * factor; }

  // A plain comment, not copied.
  int plain() { return 3; }

  int value; ///< The current value.

  /// A counter shared by all instances.
  static int counter;
};

int Documented::counter = 0;

/// Colors a documented class can have.
enum Color { Red, Green };

/// A box holding a value.
template <typename T>
struct Box {
  /// Returns the boxed value.
  T get() { return T(5); }
};

/// Adds one to *x*.
int increment(int x) { return x + 1; }
