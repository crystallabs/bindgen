// Objects handed to C++ code which keeps them in memory the GC doesn't scan.
// See Papierkorb/bindgen#75.

struct Inner {
  Inner(int x) : x(x) { }

  int x;

  // Make the object big, so the GC soon reuses its memory once collected.
  int padding[1 << 16];
};

// Not allocated by the GC: Its members don't keep anything alive.
struct Outer {
  static Outer *new_no_gc() { return new Outer; }

  Outer() { last_ = this; }

  Inner *inside = nullptr;
  Inner *other = nullptr;

  void storeInside(Inner *in) { inside = in; }
  void storeOther(Inner &in) { other = &in; }
  int sum(Inner *in, int x) { return in->x + x; }

  static Outer *last_;
  static Outer *last() { return last_; }
};

// Defined out of line, as inline variables need C++17
Outer *Outer::last_ = nullptr;

// Selects the arguments to keep alive.
struct Picky {
  Picky() { }
  Picky(Inner *in) : kept(in) { }

  Inner *kept = nullptr;

  void setBoth(Outer *outer, Inner *in, Inner *other) {
    outer->inside = in;
    outer->other = other;
  }

  void setNone(Outer *outer, Inner *in) { outer->inside = in; }
};
