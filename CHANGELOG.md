# Changelog

Notable changes to bindgen.  For releases up to 0.7.0 see the Git history.

## Unreleased

### Breaking changes

* LLVM and Clang 14 or newer are required.  Tested with 14, 19 and 22.
* Crystal 1.8 or newer is required.
* `assets/bindgen_helper.hpp` changed.  Projects which copied it into their
  `ext/` directory have to copy it again.
* The clang tool links against PCRE2 instead of PCRE.
* If `BINDGEN_DYNAMIC` is unset, static or shared linking of LLVM and Clang is
  detected.  It used to default to static linking, except on Fedora and
  openSUSE.
* `clang/find_clang.cr` writes `clang/variables.yml` instead of
  `clang/Makefile.variables`.
* Sequential container wrappers define `#unsafe_at` for the C++ accessor.
  `#unsafe_fetch` is now provided by `BindgenHelper::SequentialContainer`.
* Logging uses Crystal's `Log` directly, the `spoved` dependency is gone.
  The output and the `--debug` and `--trace` flags are unchanged.

### Added

* C arrays (#76):
  * Members of copied structures become `StaticArray`s.
  * Array members of built-in types get a getter returning a `Slice`.
* Generic container modules (#102): `Container(T)` can be used as type
  restriction, `Container.of(T)` returns the wrapper class of an instantiation
  and `.from` builds one from any `Enumerable`.
* Shared linking uses `libclang-cpp` and `libLLVM` (#66).
* `tool.sh` builds `bin/bindgen` once and reuses it.
* The clang tool's output carries a format version, so an outdated
  `clang/parser` is reported instead of being misread.
* The clang tool is built by the default C++ compiler, not necessarily by the
  `clang++` of the LLVM it links against.
* GitHub Actions workflow, replacing Travis CI.
* Ameba as development dependency with a baseline `.ameba.yml`, run in CI.
  Installing the development dependencies needs Crystal 1.19 or newer.

### Fixed

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
