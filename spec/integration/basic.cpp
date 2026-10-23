#include <cstddef>
#include <chrono>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <gc/gc.h>

class IgnoreMe { };

class Adder {
  int base;
public:
  Adder(int b) : base(b) { }

  int sum(int offset) {
    return this->base + offset;
  }

  static int sum(int a, int b) {
    return a + b;
  }

  void ignoreByName() { }
  int ignoreBySignature(int x) { return x; } // Kept
  int ignoreBySignature(int x, int y) { return x + y; } // Ignored by signature
  int ignoreByRegex(int x) { return x; } // Kept
  int ignoreByRegex(const char *s) { return -1; } // Ignored by regular expression
  void ignoreByArgument(IgnoreMe me) { }
  void ignoreByArgumentRef(IgnoreMe &me) { }
  void ignoreByArgumentPtr(IgnoreMe *me) { }
  void ignoreByArgumentCRef(const IgnoreMe &me) { }
  void ignoreByArgumentCPtr(const IgnoreMe *me) { }
  IgnoreMe ignoreByReturn() { return IgnoreMe(); }
  IgnoreMe &ignoreByReturnRef() { return *new IgnoreMe(); }
  const IgnoreMe &ignoreByReturnCRef() { return *new IgnoreMe(); }
  IgnoreMe *ignoreByReturnPtr() { return new IgnoreMe(); }
  const IgnoreMe *ignoreByReturnCPtr() { return new IgnoreMe(); }
};

struct Copyable {
  int value;

  Copyable(int v) : value(v) { }
  Copyable(const Copyable &other) : value(other.value + 1) { }

  Copyable &operator=(const Copyable &other) {
    value = other.value + 10;
    return *this;
  }

  operator int() const { return value; }
  operator bool() const { return value != 0; }

  // A pointer to a member can't be named in Crystal, this is ignored.
  typedef int Copyable::*MemberPointer;
  operator MemberPointer() const { return &Copyable::value; }
};

// Has an implicit public copy constructor, but can't be destroyed.
class Undestructible {
  ~Undestructible() { }

public:
  static int value() { return 7; }
};

// The result of an operator is converted as a whole, like
// `QDateTime::operator-` returning `std::chrono::milliseconds`.
struct Elapsed {
  int ms;
  int count() const { return ms; }
};

struct Clock {
  Elapsed operator-(const Clock &other) const { return Elapsed{ 1500 }; }
};

struct Ops {
  int operator+  (int x) const { return x * 1; }
  int operator-  (int x) const { return x * 2; }
  int operator*  (int x) const { return x * 3; }
  int operator/  (int x) const { return x * 4; }
  int operator%  (int x) const { return x * 5; }
  int operator&  (int x) const { return x * 6; }
  int operator|  (int x) const { return x * 7; }
  int operator^  (int x) const { return x * 8; }
  int operator<< (int x) const { return x * 9; }
  int operator>> (int x) const { return x * 10; }
  int operator&& (int x) const { return x * 11; }
  int operator|| (int x) const { return x * 12; }
  int operator== (int x) const { return x * 13; }
  int operator!= (int x) const { return x * 14; }
  int operator<  (int x) const { return x * 15; }
  int operator>  (int x) const { return x * 16; }
  int operator<= (int x) const { return x * 17; }
  int operator>= (int x) const { return x * 18; }
  int operator[] (int x) const { return x * 19; }

  int operator+= (int x) const { return x * 101; }
  int operator-= (int x) const { return x * 102; }
  int operator*= (int x) const { return x * 103; }
  int operator/= (int x) const { return x * 104; }
  int operator%= (int x) const { return x * 105; }
  int operator&= (int x) const { return x * 106; }
  int operator|= (int x) const { return x * 107; }
  int operator^= (int x) const { return x * 108; }
  int operator<<=(int x) const { return x * 109; }
  int operator>>=(int x) const { return x * 110; }

//  auto operator<=>(const Ops &) const = default;

  int operator+() const { return 10001; }
  int operator-() const { return 10002; }
  int operator*() const { return 10003; }
  int operator~() const { return 10004; }
  int operator!() const { return 10005; }
  int operator++() const { return 10006; }
  int operator--() const { return 10007; }
  int operator++(int) const { return 10008; }
  int operator--(int) const { return 10009; }

  int operator()() const { return 20001; }
  int operator()(int) const { return 20002; }
  int operator()(int, int) const { return 20003; }
  int operator()(bool) const { return 20004; }
};

struct FreeOps { };

int operator+  (FreeOps &, int x) { return x * 1; }
int operator-  (FreeOps &, int x) { return x * 2; }
int operator*  (FreeOps &, int x) { return x * 3; }
int operator/  (FreeOps &, int x) { return x * 4; }
int operator%  (FreeOps &, int x) { return x * 5; }
int operator&  (FreeOps &, int x) { return x * 6; }
int operator|  (FreeOps &, int x) { return x * 7; }
int operator^  (FreeOps &, int x) { return x * 8; }
int operator<< (FreeOps &, int x) { return x * 9; }
int operator>> (FreeOps &, int x) { return x * 10; }
int operator&& (FreeOps &, int x) { return x * 11; }
int operator|| (FreeOps &, int x) { return x * 12; }
int operator== (FreeOps &, int x) { return x * 13; }
int operator!= (FreeOps &, int x) { return x * 14; }
int operator<  (FreeOps &, int x) { return x * 15; }
int operator>  (FreeOps &, int x) { return x * 16; }
int operator<= (FreeOps &, int x) { return x * 17; }
int operator>= (FreeOps &, int x) { return x * 18; }

int operator+= (FreeOps &, int x) { return x * 101; }
int operator-= (FreeOps &, int x) { return x * 102; }
int operator*= (FreeOps &, int x) { return x * 103; }
int operator/= (FreeOps &, int x) { return x * 104; }
int operator%= (FreeOps &, int x) { return x * 105; }
int operator&= (FreeOps &, int x) { return x * 106; }
int operator|= (FreeOps &, int x) { return x * 107; }
int operator^= (FreeOps &, int x) { return x * 108; }
int operator<<=(FreeOps &, int x) { return x * 109; }
int operator>>=(FreeOps &, int x) { return x * 110; }

//  auto operator<=>(const FreeOps &, const FreeOps &) = default;

int operator+(FreeOps &) { return 10001; }
int operator-(FreeOps &) { return 10002; }
int operator*(FreeOps &) { return 10003; }
int operator~(FreeOps &) { return 10004; }
int operator!(FreeOps &) { return 10005; }
int operator++(FreeOps &) { return 10006; }
int operator--(FreeOps &) { return 10007; }
int operator++(FreeOps &, int) { return 10008; }
int operator--(FreeOps &, int) { return 10009; }

// Configured with conversion templates using `%` twice.
typedef int counted_t;

class TypeConversion {
  int countedCalls = 0;

public:

  char next(char c) {
    return c + 1;
  }

  // Specialized match in argument and result.  Result with decay.
  char *greet(const char *name) {
    int length = 31;
    char *buffer = static_cast<char *>(GC_malloc(length + 1));
    snprintf(buffer, length, "Hello %s!", name);
    return buffer;
  }

  // Regression test for issue #2: Void pointer yields a return in C++ wrapper.
  void *voidPointer() {
    return reinterpret_cast<void *>(0x11223344); // Don't break on 32bit!
  }

  // A `const void *` is a `Void*` too, like `QUuid::fromBytes` takes.
  const void *constVoidPointer() {
    return reinterpret_cast<const void *>(0x11223344);
  }

  long addressOf(const void *pointer) {
    return reinterpret_cast<long>(pointer);
  }

  counted_t counted() {
    return ++countedCalls;
  }

  int countedCallCount() {
    return countedCalls;
  }

  int takeCounted(counted_t value) {
    return value;
  }
};

struct ImplicitConstructor {
};

struct Aggregate {
  int x;
  double y;
  const bool z;
};

// Not an aggregate since C++20, as it declares a constructor.
struct DefaultedConstructor {
  DefaultedConstructor() = default;

  int x;
  double y;
};

// `std::atomic` can't be copied or moved, and so can't this aggregate.
struct NonMovableAggregate {
  int x;
#if __cplusplus >= 201703L
  std::atomic<int> counter;
#else // Can't be initialized from an `int` without a copy before C++17.
  int counter;
#endif

  int sum() {
    return x + counter;
  }
};

class PrivateConstructor {
  PrivateConstructor();
};

struct DeletedConstructor {
  DeletedConstructor() = delete;
};

struct PlainStruct {
  int x;
  int *xp;
  int y[4];
  int *yp[6];
  int z[8][16];
  void *vp;
  void **vpp;
};

// A method named like a Crystal reserved method is prefixed: `#cpp_initialize`.
struct Init {
  bool ready = false;
  void initialize() { ready = true; }
  bool check() { return ready; }
};

// A pointer argument defaulting to `nullptr` defaults to `nil` in Crystal.
struct Flags {
  int flagged(bool *flag = nullptr) {
    if (flag) *flag = true;
    return flag ? 1 : 0;
  }
};

// A deduced `auto` return type is named by the deduced type.
struct Deduced {
  struct Inner { int v; };
  auto inner() { return Inner { 4 }; }
  auto number() { return 9; }
};

// An operator Crystal can't name is dropped instead of aborting.
struct Arrow {
  int value = 3;
  Arrow *operator->() { return this; }
  int ok() { return 1; }
};

// A parameter named like a Crystal keyword is renamed.
struct Params {
  static int keep(int self, int nil) { return self + nil; }
};

// A friend operator taking the class by value, like Qt's
// `operator==(QDate lhs, QDate rhs)`, is wrapped like one taking a reference.
struct ValueOps {
  int n;
  ValueOps(int n) : n(n) { }
  friend bool operator==(ValueOps lhs, ValueOps rhs) { return lhs.n == rhs.n; }
  friend int operator+(ValueOps lhs, int x) { return lhs.n + x; }
};

// A deleted operator is skipped.
struct DeletedOps {
  friend bool operator==(DeletedOps, DeletedOps) = delete;
};

// A templated friend operator has no concrete signature, so it's skipped.
struct Stream {
  int n = 0;
  template <typename T>
  friend Stream &operator<<(Stream &stream, const T &value) { stream.n++; return stream; }
  int count() { return n; }
};

// A copied structure wrapped as a Crystal `struct` gets property methods,
// and rules shared through a YAML anchor are copied per type.
struct Pixel {
  int x;
  int y;
};

struct Pixel2 {
  int x;
  int y;
};

// A typedef of a typedef with rules: `Millis` resolves to
// `std::chrono::milliseconds`, not to the canonical `std::chrono::duration<...>`.
typedef std::chrono::milliseconds Millis;

struct Timing {
  Millis wait() { return Millis(250); }
  long twice(Millis millis) { return millis.count() * 2; }
};

// A wrapped class named like a Crystal class bindgen's glue uses.
struct Mutex {
  int lock() { return 1; }
};

// A std-style alias of a method collides with it in Crystal: the first wins.
struct Lockable {
  int tryLock() { return 1; }
  int try_lock() { return 2; }
  int tryAcquire(int n = 1) { return n; }
  int try_acquire() { return -1; } // Would replace `try_acquire(n = 1)` in Crystal
};

// A `std::nullptr_t` overload is dropped.
struct NullSink {
  int take(std::nullptr_t) { return 0; }
  int take(int value) { return value; }
};

// A class wrapped under its C++ name: Its nested enum is still reachable
// from `lib Binding`, whose alias of the class would shadow it.
struct Mode {
  enum Kind { Fast, Slow };
  static int pick(Kind kind) { return kind; }
};
