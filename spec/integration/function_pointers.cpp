/* Function pointers as members of copied structures. */

#include <cstddef>
#include <string>

struct Point {
  int x, y;
};

typedef int (*BinaryOp)(int, int);

// Another calling convention than the target's.
#if defined(__x86_64__) && !defined(_WIN32)
#define OTHER_ABI __attribute__((ms_abi))
#else
#define OTHER_ABI
#endif

struct Ops {
  BinaryOp add; // Through a typedef
  int (*negate)(int);
  void (*clear)(Point *point); // No result, pointer to a copied structure
  int (*sum)(Point point); // Copied structure by value
  int (*apply)(BinaryOp op, int a, int b); // Function pointer argument, `Void *`

  // These become `Void` pointers.
  int (*variadic)(int count, ...);
  int (OTHER_ABI *foreign)(int);
  int (*converted)(std::string name);
  BinaryOp table[2];
  BinaryOp *indirect;
};

// Has a wrapper class, which has no methods for the function pointers.
struct Callbacks {
  int (*twice)(int);
  int value;
};

static int add(int a, int b) { return a + b; }
static int negate(int value) { return -value; }
static void clear(Point *point) { point->x = 0; point->y = 0; }
static int sum(Point point) { return point.x + point.y; }
static int apply(BinaryOp op, int a, int b) { return op(a, b); }

static BinaryOp shared_add = add;

Ops ops_make() {
  Ops ops = { };
  ops.add = add;
  ops.negate = negate;
  ops.clear = clear;
  ops.sum = sum;
  ops.apply = apply;
  ops.table[0] = add;
  ops.indirect = &shared_add;
  return ops;
}

static int twice(int value) { return value * 2; }
Callbacks ops_callbacks() { return Callbacks { twice, 7 }; }

// Calls the `negate` member, which may be set in Crystal.
int ops_call_negate(Ops ops, int value) { return ops.negate(value); }

// The C++ layout, to compare with the `lib struct`.
int ops_size() { return sizeof(Ops); }
int ops_offset_indirect() { return offsetof(Ops, indirect); }
