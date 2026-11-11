/* Structures configured by the name of a typedef. */

typedef struct { int x, y; } Anonymous; // Named only by the typedef
typedef struct Tagged_ { int a; } Tagged; // Configured by the typedef name
typedef struct Same { int b; } Same; // Tag and typedef named alike

typedef struct Forward_ Forward; // Before the definition
struct Forward_ { int c; };

struct User {
  Anonymous anonymous;
  Tagged by_typedef;
  struct Tagged_ by_tag; // Still `Tagged`
  Same same;
  Forward *forward;
};

// Has a wrapper class.
typedef struct { int z; } Wrapped;

int anonymous_sum(Anonymous value) { return value.x + value.y; }
Anonymous anonymous_make(int x, int y) { return Anonymous { x, y }; }
int anonymous_wrapped_z(Wrapped *value) { return value->z; }
