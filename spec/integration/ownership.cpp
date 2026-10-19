// Objects handed to C++ code which keeps them in memory the GC doesn't scan.
// See Papierkorb/bindgen#75.

struct Inner {
  Inner(int x) : x(x) { }

  int x;

  // Make the object big, so the GC soon reuses its memory once collected.
  int padding[1 << 16];
};

// A struct wrapped as a Crystal struct, which keep_alive must skip.
struct Plain {
  int value;
};

// Not allocated by the GC: Its members don't keep anything alive.
struct Outer {
  static Outer *new_no_gc() { return new Outer; }

  Outer() { last_ = this; }

  Inner *inside = nullptr;
  Inner *other = nullptr;
  Plain *plain_ = nullptr;

  void storeInside(Inner *in) { inside = in; }
  void storePlain(Plain *plain) { plain_ = plain; }
  void storeOther(Inner &in) { other = &in; }
  int sum(Inner *in, int x) { return in->x + x; }

  static Outer *last_;
  static Outer *last() { return last_; }
};

// Defined out of line, as inline variables need C++17
Outer *Outer::last_ = nullptr;

// Counts its live instances, to see when the GC destroys them.
struct Counted {
  Counted() { ++alive_; }
  ~Counted() { --alive_; }

  static int alive() { return alive_; }

private:
  static int alive_;
};

int Counted::alive_ = 0;

// Refers to its constructor argument through memory the GC doesn't scan, and
// uses it when destroyed, like an iterator unregistering from its container.
// `depends_on:` makes the GC destroy it before the `Counted`.
struct Dependent {
  Dependent(Counted *counted) : d(new Data{counted}) { }
  Dependent(const Dependent &other) : d(new Data{other.d->counted}) { }

  ~Dependent() {
    ++destroyed_;
    counted_alive_at_destruction_ = Counted::alive();
    delete d;
  }

  static int destroyed() { return destroyed_; }
  static int countedAliveAtDestruction() { return counted_alive_at_destruction_; }

private:
  struct Data { Counted *counted; };
  Data *d;

  static int destroyed_;
  static int counted_alive_at_destruction_;
};

int Dependent::destroyed_ = 0;
int Dependent::counted_alive_at_destruction_ = -1;

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
