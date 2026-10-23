// Objects handed to C++ code which keeps them in memory the GC doesn't scan.
// See Papierkorb/bindgen#75.

#include <cstdlib>

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

// Re-declares a method of Outer, like an override: The keep_alive rules of
// Outer cover it, without rules of its own.
struct SubOuter : Outer {
  static SubOuter *new_no_gc() { return new SubOuter; }

  void storeInside(Inner *in) { inside = in; }
};

// Counts its live instances, to see when the GC destroys them.  The destructor
// is virtual, so `delete` through a `Counted *` destroys the wrapper, as it
// does for a Qt object.
struct Counted {
  Counted() { ++alive_; }
  virtual ~Counted() { --alive_; }

  static int alive() { return alive_; }

private:
  static int alive_;
};

int Counted::alive_ = 0;

// Refers to its constructor argument through memory the GC doesn't scan, and
// uses it when destroyed, like an iterator unregistering from its container.
// `depends_on:` makes the GC destroy it before the `Counted`.  `retarget`
// replaces it, like `QTextStream::setDevice`.
struct Dependent {
  Dependent(Counted *counted) : d(new Data{counted}) { }
  Dependent(const Dependent &other) : d(new Data{other.d->counted}) { }

  ~Dependent() {
    ++destroyed_;
    counted_alive_at_destruction_ = Counted::alive();
    delete d;
  }

  // Not constructed from Crystal: `depends_on:` of a method does nothing.
  static Dependent *newNoGc(Counted *counted) { return new Dependent(counted); }

  void retarget(Counted *counted) { d->counted = counted; }
  Counted *target() const { return d->counted; }

  // Matched by `depends_on:`, which ignores it as it has no object.
  static bool targets(const Dependent *dependent, Counted *counted) { return dependent->d->counted == counted; }

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

// Like `Dependent`, with a virtual method: Crystal constructs the shadow
// subclass of `Processor::VirtualOverride`, like a Qt widget.
struct VirtualDependent {
  VirtualDependent() : d(new Data{nullptr}) { }

  virtual ~VirtualDependent() {
    ++destroyed_;
    counted_alive_at_destruction_ = Counted::alive();
    delete d;
  }

  virtual int kind() { return 1; }
  int callKind() { return kind(); }

  void retarget(Counted *counted) { d->counted = counted; }
  Counted *target() const { return d->counted; }

  static int destroyed() { return destroyed_; }
  static int countedAliveAtDestruction() { return counted_alive_at_destruction_; }

private:
  struct Data { Counted *counted; };
  Data *d;

  static int destroyed_;
  static int counted_alive_at_destruction_;
};

int VirtualDependent::destroyed_ = 0;
int VirtualDependent::counted_alive_at_destruction_ = -1;

// Checks where the `BindgenGCObject` of an object constructed from Crystal is,
// which the glue of a method configured in `depends_on:` finds by `GC_base`.
// The parser doesn't see `bindgen_helper.hpp`, only the compiler does.
struct Layout {
  // At the start of the allocation of a `CrystalGCCleanupWrapper<Dependent>`.
  static bool atBase(Dependent *dependent);

  // At the start of the allocation of the wrapper of the shadow subclass of
  // `VirtualDependent`, also a dynamic class, which the glue found.
  static bool atBase(VirtualDependent *dependent);

  // Is *dependent* constructed from Crystal?
  static bool isBindingObject(Dependent *dependent);
};

#ifdef BINDGEN_HELPER_HPP
bool Layout::atBase(Dependent *dependent) {
  auto *wrapper = static_cast<CrystalGCCleanupWrapper<Dependent> *>(dependent);
  return reinterpret_cast<BindgenGCObject *>(GC_base(dependent)) == static_cast<BindgenGCObject *>(wrapper) &&
         bindgen_gc_object(dependent) == static_cast<BindgenGCObject *>(wrapper);
}

bool Layout::atBase(VirtualDependent *dependent) {
  BindgenGCObject *object = bindgen_gc_object(dependent);
  return object != nullptr && reinterpret_cast<BindgenGCObject *>(GC_base(dependent)) == object &&
         static_cast<void *>(object) != static_cast<void *>(dependent);
}

bool Layout::isBindingObject(Dependent *dependent) {
  return bindgen_gc_object(dependent) != nullptr;
}
#else
bool Layout::atBase(Dependent *) { return false; }
bool Layout::atBase(VirtualDependent *) { return false; }
bool Layout::isBindingObject(Dependent *) { return false; }
#endif

// Two objects owning each other through memory the GC doesn't scan: The one
// destroyed first deletes the other, like a Qt parent deletes its children.
// Collected together, the GC queued the finalizers of both, so the deleted one
// must not be finalized again.  (The link is allocated with `malloc`, as
// libgccpp replaces `operator new` with GC memory the GC scans.)
struct Mutual {
  Mutual() : link(static_cast<Link *>(std::malloc(sizeof(Link)))) { link->other = nullptr; }

  virtual ~Mutual() {
    ++destroyed_;
    if (Mutual *other = link->other) {
      other->link->other = nullptr;
      delete other;
    }
    std::free(link);
  }

  void pairWith(Mutual *other) {
    link->other = other;
    other->link->other = this;
  }

  static int destroyed() { return destroyed_; }

private:
  struct Link { Mutual *other; };
  Link *link;

  static int destroyed_;
};

int Mutual::destroyed_ = 0;

// Owns the `Counted` handed to it, like a Qt parent owns its children, and
// deletes it when destroyed or told to.  `keep_alive:` keeps the `Counted` for
// it, and the delete releases it again.
struct Owner {
  ~Owner() { delete child; }

  void adopt(Counted *counted) { child = counted; }

  void disown() {
    delete child;
    child = nullptr;
  }

  // Hand the child back without deleting it, like `QLayout::takeAt` or
  // `QLayout::removeWidget`: `release:` releases the result or the argument.
  Counted *takeChild() {
    Counted *taken = child;
    child = nullptr;
    return taken;
  }

  void removeChild(Counted *counted) {
    if (child == counted) child = nullptr;
  }

  // Hands `old` back and keeps `replacement`: `release:` and `keep_alive:`.
  Counted *swapChild(Counted *old, Counted *replacement) {
    if (child != old) return nullptr;
    child = replacement;
    return old;
  }

  Counted *child = nullptr;
};

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
