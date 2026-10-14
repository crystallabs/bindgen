#include <stdarg.h>

extern "C" int extern_one() {
  return 1;
}

extern "C" int extern_sum(int count, ...) {
  va_list ap;
  va_start (ap, count);

  int sum = 0;
  for (int i = 0; i < count; i++) {
    sum += va_arg(ap, int);
  }

  va_end (ap);
  return sum;
}

namespace scope {
  extern "C" int scope_five() {
    return 5;
  }
}

struct class_t { };

extern "C" {
  int extern_two() {
    return 2;
  }

  struct class_t *class_new() {
    return (struct class_t *)0;
  }

  int class_three(struct class_t *) {
    return 3;
  }

  int class_four() {
    return 4;
  }
}
