# Changelog

Notable changes to bindgen.  For releases up to 0.7.0 see the Git history.

## Unreleased

### Breaking changes

* LLVM and Clang 14 or newer are required.  Tested with 14 to 23.
* Crystal 1.8 or newer is required.
* `assets/bindgen_helper.hpp` changed.  Projects which copied it into their
  `ext/` directory have to copy it again.
* The clang tool links against PCRE2 instead of PCRE.
* If `BINDGEN_DYNAMIC` is unset, static or shared linking of LLVM and Clang is
  detected.  It used to default to static linking, except on Fedora and
  openSUSE.
* `clang/find_clang.cr` writes `clang/variables.yml` instead of
  `clang/Makefile.variables`.
* `clang/find_clang.cr` no longer reads `CPPFLAGS` and `LDFLAGS`, and looks
  for the LLVM and Clang libraries only in LLVM's library directory.
* Sequential container wrappers define `#unsafe_at` for the C++ accessor.
  `#unsafe_fetch` is now provided by `BindgenHelper::SequentialContainer`.
* Classes declaring any constructor, including `= default` and `= delete`,
  no longer get an aggregate constructor: they aren't aggregates in C++20.
* Wrapper classes of `copy_structure` types get property methods for the
  fields.  Set `instance_variables: false` to turn them off.
* Copying a structure with members a `lib struct` can't hold (`std::string`,
  containers, classes by value, references, pointers to arrays, unknown types)
  is an error.  It used to emit
  invalid or layout-incompatible Crystal.
* Copying a structure which isn't trivially copyable and standard-layout is an
  error.
* `bindgen_helper.hpp` disables clang's `-Wreturn-type-c-linkage`.
* `Binding::CrystalSlice` gained a `read_only` field after `ptr` and `size`,
  and `bindgen_helper.hpp` defines the matching C++ `struct CrystalSlice`.
  Projects defining their own C++ `CrystalSlice` have to use this one.

### Added

* C arrays (#76):
  * Members of copied structures become `StaticArray`s.
  * Array members of built-in types get a getter returning a `Slice`.
* Generic container modules (#102): `Container(T)` can be used as type
  restriction, `Container.of(T)` returns the wrapper class of an instantiation
  and `.from` builds one from any `Enumerable`.
* `#to?(T.class)` casts between wrapper classes, down to polymorphic
  sub-classes through `dynamic_cast` (#87).
* Shared linking uses `libclang-cpp` and `libLLVM` (#66).
* `tool.sh` builds `bin/bindgen` once and reuses it.
* The clang tool's output carries a format version, so an outdated
  `clang/parser` is reported instead of being misread.
* The clang tool is built by the default C++ compiler, not necessarily by the
  `clang++` of the LLVM it links against.
* CMake runs `clang/find_clang.cr` once instead of three times, and shows its
  diagnostics (#51).  The script asks `llvm-config` and `clang++` for most
  paths instead of parsing a compiler command line (#36).
* Static builds link only the Clang and LLVM libraries the tool needs.
* `BINDGEN_CLANG_FLAGS` passes extra flags to `clang++` when looking for the
  C++ standard library, e.g. `-stdlib=libc++`.
* Named members of anonymous `struct` and `union` types in wrapped classes get
  property methods (#85).  The getter returns a wrapper class like
  `Wrapped::Unnamed1`, which refers to the member inside the object.
* Copy constructors (`.new(other)`), assignment operators (`#assign!`) and
  conversion operators (`#to_bool` for `operator bool()`) are wrapped.
* The integration specs are parsed in the C++ standard they're built in.
* The clang tool can be built out of tree (`cmake -S clang -B build/llvm-19`),
  keeping a build directory per LLVM version.
* Logging uses Crystal's `Log` directly, the `spoved` dependency is gone.
  The output and the `--debug` and `--trace` flags are unchanged.
* GitHub Actions workflow, replacing Travis CI.
* Ameba as development dependency with a baseline `.ameba.yml`, run in CI.
  Installing the development dependencies needs Crystal 1.19 or newer.

### Fixed

* Overriding one overload of a C++ virtual method in Crystal hooked all
  overloads of that name, recursing endlessly in the others.  Only overloads
  accepting the C++ argument types are hooked.
* Pointers to converted types, like `std::string *`, in copied structures
  become `Void*` instead of being rejected.
* Building and running on macOS with Homebrew: LLVM, PCRE2 and the libraries
  LLVM depends on are found, the SDK's C headers are searched, and `tool.sh`
  no longer requires coreutils.
* Static linking against LLVM 23.
* Constructors of aggregates, unions and of types with a `from_cpp` converter
  generated C++ code which didn't compile.
* `find_path` regular expressions were compiled with the dot-all instead of the
  multi-line option on Crystal 1.8 and newer.
* The clang tool crashed when a class template was listed in `classes` (#117).
  It now reports an error.
* The clang tool no longer leaves through `exit()` to avoid a crash in Clang's
  destructors (#37).  Macros are evaluated in a second parsing pass.
* Containers without instantiations, and containers in an implementation
  namespace like `std::__1::vector`, broke the container modules.
* The top-level `CMakeLists.txt` builds the parser and `bin/bindgen` again.
* Aggregate constructors no longer require the type to be movable.  Aggregates
  are allocated as themselves and initialized in place.
* The destructor of a garbage collected C++ union is run.
* Bit-fields are reported by the clang tool.  Copying a structure with a
  bit-field is refused, as Crystal can't describe its layout.
* GNU-style variadic macros (`args...`) are no longer dropped.
* `functions:` keys with a namespace (`ns::(.*)`) are matched as documented.
  Function classes accept qualified names in `constructors:` and
  `destructor:`.
* `TEMPLATE.yml` no longer documents the non-existent `kind: Value`.
* A `std::string` returned by value pointed into a destroyed temporary, and
  the function was called twice.  The same double call happened for virtual
  methods returning a string which are overridden in Crystal.
* The destructor of a class or container returned by value is run.
* Wrapper classes of `copy_structure` types compile and work (#21).
* A conversion template of `types:` using `%` more than once evaluated the
  expression, commonly a call, once per use.
* Property methods of protected members were dropped if `instance_properties`
  ran before `filter_methods`, as in the default processor order.
* A type listed in `enums:` or `classes:` and in `types:` without `kind:` got
  kind `Class`.
* A function matched by several `functions:` keys was bound once per key.  The
  first key now wins.
* The sanity check printed only the number of errors, not the errors.
* A method returning, or a data member of, a pointer to a by-value type like
  `std::string *` generated C++ that didn't compile.  It is now ignored, like
  arguments of such types already were.
* A copied structure passed by value to or returned from a Crystal override of
  a virtual method was garbled, and returning one without a wrapper class
  didn't compile.
* A `final` class or virtual method was sub-classed or overridden in C++,
  which failed to compile.
* Inherited virtual methods of a second base class were called with an
  unadjusted `this` pointer.  Its non-virtual methods are wrapped too.
* A property method of a data member clashing with a method of the same
  Crystal name, like `drop_action` and `dropAction()`, is no longer generated.
* Methods and data members using an unknown template instantiation, like
  `QScopedPointer<QObjectData>`, are ignored.  They produced an invalid alias.
* Methods of a second base overloaded only in constness were wrapped twice,
  an ambiguous call.
* Conversion operators to types without rules, like a pointer to a member,
  are ignored.
* Downcasts compile without RTTI (`-fno-rtti`), and abort when called.
* A virtual method of a second base overridden as private in the derived class
  was called through it, which didn't compile.
