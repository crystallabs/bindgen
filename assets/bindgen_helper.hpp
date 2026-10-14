/* This file is part of bindgen
 *   See: https://github.com/Papierkorb/bindgen
 *
 * This file is licensed under the following "public domain" license.
 * IT APPLIES ONLY TO THIS FILE `bindgen_helper.h` AND NOT TO ANY OTHER FILE.
 *
 * This is free and unencumbered software released into the public domain.
 *
 * Anyone is free to copy, modify, publish, use, compile, sell, or
 * distribute this software, either in source code form or as a compiled
 * binary, for any purpose, commercial or non-commercial, and by any
 * means.
 *
 * In jurisdictions that recognize copyright laws, the author or authors
 * of this software dedicate any and all copyright interest in the
 * software to the public domain. We make this dedication for the benefit
 * of the public at large and to the detriment of our heirs and
 * successors. We intend this dedication to be an overt act of
 * relinquishment in perpetuity of all present and future rights to this
 * software under copyright law.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
 * OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 *
 * For more information, please refer to <http://unlicense.org/>
 */

 /*********************** TAKE CARE WHEN CHANGING THINGS ***********************
 * This file may be a symlink, pointing at the `bindgen_helper.hpp` inside the *
 * shard installation directory of `bindgen`.  It is *not* a local copy!   If  *
 * you want to make changes, make sure that you have your own copy first, and  *
 * only then do changes.  Otherwise a bindgen update may override your changes.*
 ******************************************************************************/

#ifndef BINDGEN_HELPER_HPP
#define BINDGEN_HELPER_HPP

#include <gc/gc.h> // Boehm GC
#include <string.h>
#include <stdlib.h> // abort()
#include <stdio.h> // fprintf()

// Helper structure to transfer a `String` between C/C++ and Crystal.
typedef struct CrystalString { // C compatibility
  const char *ptr;
  int size;
} CrystalString;

// Compiler branching hint
#define bindgen_likely(x) __builtin_expect(!!(x), 1)

static __attribute__((noreturn)) void bindgen_fatal_panic(const char *message) {
  fprintf(stderr, "Fatal error in bindings: %s\n", message);
  abort();
}

#ifdef __cplusplus
#include <gc/gc_cpp.h>
#include <string>
#include <type_traits>
#include <utility>

// The wrapper functions return copied structures by value, which Crystal knows
// as `lib struct` of the same layout.  Clang warns if such a type isn't a POD,
// which already is the case if it has a constructor.
#ifdef __clang__
#pragma clang diagnostic ignored "-Wreturn-type-c-linkage"
#endif

// Break C++'s encapsulation to allow easy wrapping of protected methods.
#define protected public

// The result points into `str`, whose owner has to keep it alive.
static CrystalString bindgen_stdstring_to_crystal(const std::string &str) {
  return CrystalString{ str.data(), static_cast<int>(str.size()) };
}

// A temporary, like the result of a function returning a `std::string` by
// value, is destroyed before the wrapper function returns.  Its bytes are
// copied into memory owned by the GC, so that they outlive the call.
static CrystalString bindgen_stdstring_to_crystal(const std::string &&str) {
  char *copy = static_cast<char *>(GC_MALLOC_ATOMIC(str.size() + 1));
  memcpy(copy, str.data(), str.size());
  copy[str.size()] = '\0';
  return CrystalString{ copy, static_cast<int>(str.size()) };
}

static std::string bindgen_crystal_to_stdstring(CrystalString str) {
  return std::string(str.ptr, str.size);
}

/* Wrapper for a Crystal `Slice`.  Layout-compatible to `Slice`. */
/* Wrapper for a Crystal `Slice`, see `Binding::CrystalSlice`.  `pointer` and
 * `size` lead, as in earlier versions which lacked `read_only`.
 */
struct CrystalSlice {
  const void *pointer;
  int size;
  bool read_only;
};

template<typename T, std::size_t N>
/*constexpr*/ CrystalSlice bindgen_array_to_slice(T (&arr)[N]) noexcept {
  return CrystalSlice{ arr, static_cast<int>(N), std::is_const<T>::value };
}

/* Wrapper for a Crystal `Proc`. */
template<typename T, typename ... Args>
struct CrystalProc {
  union {
    T (*withSelf)(void *, Args ...);
    T (*withoutSelf)(Args ...);
  };

  void *self;

  CrystalProc() : withSelf(nullptr), self(nullptr) { }

  inline bool isValid() const {
    return (withSelf != nullptr);
  }

  /* Fun fact: If the Crystal `Proc` doesn't capture any context, it won't
   * allocate any - But also don't expect any!  We have to accomodate for this
   * by only passing `this->self` iff it is non-NULL.
   */

  T operator()(Args ... arguments) const {
    if (this->self) {
      return this->withSelf(this->self, arguments...);
    } else {
      return this->withoutSelf(arguments...);
    }
  }
};

template <typename T>
struct CrystalGCCleanupWrapper: public T, public gc_cleanup
{
  using T::T;
};

// Unions can't be inherited from, these are allocated as they are.  This
// doesn't run their destructor: bindgen uses `bindgen_gc_finalizer` instead.
template <typename T>
using CrystalGCWrapper = typename std::conditional<
  std::is_union<T>::value, T, CrystalGCCleanupWrapper<T>>::type;

template <typename T>
struct BindgenGCFinalizer {
  static void GC_CALLBACK run(void *object, void *) {
    static_cast<T *>(object)->~T();
  }

  static GCCleanUpFunc get(std::true_type /* trivially destructible */) {
    return nullptr;
  }

  static GCCleanUpFunc get(std::false_type) {
    return &BindgenGCFinalizer<T>::run;
  }
};

/* Finalizer for a `T` that is allocated as it is, instead of being wrapped in
 * a `CrystalGCWrapper`: `new (UseGC, bindgen_gc_finalizer<T>()) T { ... }`.
 * Aggregates are allocated like this, as only `T` itself can be initialized
 * from a braced list without copying or moving it, and so are unions.  Returns
 * a null pointer if `T` doesn't need a finalizer.
 */
template <typename T>
GCCleanUpFunc bindgen_gc_finalizer() {
  return BindgenGCFinalizer<T>::get(std::is_trivially_destructible<T>());
}

/// A simple wrapper around a non-pointer type that allows a single
/// dereference operation.
template <typename T>
struct bg_deref {
  T data;

  template<typename... Args>
  bg_deref(Args&&... args) : data(std::forward<Args>(args)...) {}

  T operator*() && { return std::move(data); }

  // Allows passing the value straight on into a converter function.
  operator T() && { return std::move(data); }
};

#endif // __cplusplus
#endif // BINDGEN_HELPER_HPP
