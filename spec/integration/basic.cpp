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

class TypeConversion {
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
};

struct ImplicitConstructor {
};

struct Aggregate {
  int x;
  double y;
  const bool z;
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
