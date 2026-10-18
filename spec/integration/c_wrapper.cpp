#include <cstdlib>
#include <cstring>

/* Macro tests */
#define CONSTANT_ONE 1
#define CONSTANT_TWO 2
#define CONSTANT_THREE "Three"

#define VALUE_INT32 1
#define VALUE_INT64 1LL
#define VALUE_UINT64 1LLU
#define VALUE_UINT32 1U
#define VALUE_NEGATIVE_INT32 -123
#define VALUE_NEGATIVE_INT64 -123LL
#define VALUE_LARGE_UINT64 9223372036854775808
#define VALUE_LARGE_INT64 9223372036854775807
#define VALUE_TRUE true
#define VALUE_FALSE false
#define VALUE_FLOAT 3.5
#define VALUE_UNEVALUABLE __attribute__((used)) constexpr inline // Not an expression

#define ANOTHER_A "A"
#define ANOTHER_B "B"
#define ANOTHER_C "C"

#define FORCED_A 1
#define FORCED_B 2L
#define FORCED_C 3LL
#define FORCED_D 4LLU
#define FORCED_E 5.9

#define ENUM_ONE 1
#define ENUM_TWO 2
#define ENUM_THREE 3

#define FLAGS_ONE 1
#define FLAGS_TWO 2
#define FLAGS_FOUR 4

#define COMPLEX_ADD(x) (x + 1)
#define STR(x) #x
#define STRINGIFY(x) STR(x)

#define COMPLEX_A 1 | 2
#define COMPLEX_B COMPLEX_ADD(4)
#define COMPLEX_C STRINGIFY(FooBar)

/* Function mapping */

// Simple cases
int one() { return 1; }   // Short-hand
int two() { return 2; }   // Full name
int three() { return 3; } // Short-hand, One capture group
int four() { return 4; }  // One capture group


// Test crystalize_names configuration option
static int foo = 0;

// `crystalize_names: true`
void crystalize_set_foo(int value) { foo = value; }
int crystalize_get_foo() { return foo; }
bool crystalize_is_foo_zero() { return (foo == 0); }

// `crystalize_names: UNSET` Should default to false.
void dont_crystalize_set_foo(int value) { foo = value; }
int dont_crystalize_get_foo() { return foo; }
bool dont_crystalize_is_foo_zero() { return (foo == 0); }

extern "C" {
// Test simple name rewriting: /mycalc_(.*)/ -> "\1"
int mycalc_add(int a, int b) { return a + b; }
int mycalc_sub(int a, int b) { return a - b; }

// Test individual nesting: /thing_([^_]+)_(.*)/ -> "\1::\2"
int thing_increment_one(int v) { return v + 1; }
int thing_decrement_one(int v) { return v - 1; }
} // extern "C"

// Functions in a namespace.  Their qualified name is `storage::read_one`.
namespace storage {
int read_one() { return 1; } // Key is the qualified name
int read_two() { return 2; }
int write_one() { return 10; } // Key is the bare name
int raw_get() { return 20; } // Key matches the qualified and the bare name

namespace deep {
int read_three() { return 3; } // Nested namespace
} // namespace deep
} // namespace storage

// C-with-classes wrapper of functions in a namespace.
struct counter {
  int value;
};

namespace counting {
counter *counter_new() { // Constructor
  counter *c = static_cast<counter *>(malloc(sizeof(counter)));
  c->value = 0;
  return c;
}

void counter_free(counter *c) { free(c); } // Destructor
void counter_add(counter *c, int by) { c->value += by; } // Member
int counter_get_value(counter *c) { return c->value; } // Getter member
int counter_limit() { return 99; } // Static
} // namespace counting

// C-with-classes wrapper test.  `crystalize_names: UNSET` should default to true.
struct string_buffer {
  char *ptr;
  int size;
};

extern "C" {
string_buffer *buffer_new() { // Constructor
  string_buffer *buf = static_cast<string_buffer *>(malloc(sizeof(string_buffer)));
  buf->ptr = nullptr;
  buf->size = 0;
  return buf;
}

string_buffer *buffer_new_string(const char *string) { // Constructor
  string_buffer *buf = static_cast<string_buffer *>(malloc(sizeof(string_buffer)));
  buf->size = strlen(string);
  buf->ptr = static_cast<char *>(malloc(buf->size + 1));
  memcpy(buf->ptr, string, buf->size);
  buf->ptr[buf->size] = 0;
  return buf;
}

void buffer_free(string_buffer *buf) { // Destructor
  free(buf->ptr);
  free(buf);
}

bool buffer_is_empty(string_buffer *buf) { // Question member
  return (buf->size == 0);
}

void buffer_set_size(string_buffer *buf, int size) { // Setter member
  buf->size = size;
  buf->ptr = static_cast<char *>(realloc(buf->ptr, size + 1));
  buf->ptr[buf->size] = 0;
}

int buffer_get_size(string_buffer *buf) { // Getter Member
  return buf->size;
}

char *buffer_string(string_buffer *buf) { // Member
  return buf->ptr;
}

void buffer_append(string_buffer *buf, const char *string) { // Member
  int added = strlen(string);

  buf->ptr = static_cast<char *>(realloc(buf->ptr, buf->size + added + 1));
  memcpy(buf->ptr + buf->size, string, added);

  buf->size += added;
  buf->ptr[buf->size] = 0;
}

int buffer_version() { // Static
  return 123;
}

} // extern "C"

// C-with-classes wrapper test.  `crystalize_names: false`
struct my_int {
  int value;
};

my_int *my_int_new() {
  return static_cast<my_int *>(calloc(1, sizeof(my_int)));
}

void my_int_free(my_int *inst) { free(inst); }
void my_int_set_value(my_int *inst, int value) { inst->value = value; }
int my_int_get_value(my_int *inst) { return inst->value; }
bool my_int_is_zero(my_int *inst) { return (inst->value == 0); }
