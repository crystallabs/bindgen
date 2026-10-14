// Classes returned by value.  These aren't copied structures, so the wrapper
// function has to move the result into memory owned by the GC, which then has
// to run its destructor.

static int trackedAlive = 0;

class Tracked {
  int m_value;

public:
  Tracked(int value) : m_value(value) { trackedAlive++; }
  Tracked(const Tracked &other) : m_value(other.m_value) { trackedAlive++; }
  ~Tracked() { trackedAlive--; }

  int value() const { return m_value; }

  Tracked twice() const { return Tracked(m_value * 2); }

  static Tracked make(int value) { return Tracked(value); }
  static int alive() { return trackedAlive; }
};

Tracked tracked_make(int value) {
  return Tracked(value);
}

// A polymorphic type with more than one base class.
static int polymorphicAlive = 0;

struct First {
  int first = 1;
  virtual ~First() { }
  virtual int which() const { return 1; }
};

struct Second {
  int second = 2;
  virtual ~Second() { }
  virtual int other() const { return 2; }
};

struct Polymorphic : public First, public Second {
  int m_value;

  Polymorphic(int value) : m_value(value) { polymorphicAlive++; }
  Polymorphic(const Polymorphic &other) : First(other), Second(other), m_value(other.m_value) {
    polymorphicAlive++;
  }

  ~Polymorphic() override { polymorphicAlive--; }

  int which() const override { return 3; }
  int value() const { return m_value; }

  static Polymorphic make(int value) { return Polymorphic(value); }
  static int alive() { return polymorphicAlive; }
};

// Doesn't need a destructor call at all.
class Trivial {
  int m_value;

public:
  Trivial(int value) : m_value(value) { }

  int value() const { return m_value; }

  static Trivial make(int value) { return Trivial(value); }
};
