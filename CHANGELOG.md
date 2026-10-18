# Changelog

Notable changes to bindgen.  For releases up to 0.7.0 see the Git history.

## Unreleased

### Added

* `<<+: file.yml` deep-merges a dependency into the configuration mapping:
  mappings under the same key merge recursively and sequences concatenate,
  where `<<:` keeps only the later value.  See "Deep merge" in the README.

### Fixed

* The bundled system include paths are no longer prefixed with the sysroot,
  which made them unusable with macOS' SDK.

## 0.10.0 (2026-10-18)

### Added

* Copied structures and unions support bit-fields, through getter and setter
  methods of their `lib struct` or `lib union`.  The type option `bit_fields` chooses between calling
  C++ accessors (`Accessors`, the default) and shifting and masking the bits in
  Crystal (`Inline`).  The clang tool's output format changed, rebuild it.
* Documentation comments of classes, methods, fields, enums and functions are
  copied into the Crystal wrappers.  `all_comments: true` under `parser:`
  copies plain comments too.
* `CONFIGURATION.md` describes every key of the configuration file (#55).  A
  spec fails if a configuration key or a key of `TEMPLATE.yml` is missing in
  it.

### Changed

* `shard.yml` no longer caps the Crystal version at 2.0.0.

### Fixed

* `keep_alive:` skips arguments whose type is a `kind: Struct` wrapper;
  passing one made the generated wrapper call `BindgenHelper.keep_alive` with a
  pointer, which doesn't compile.
* A copied structure packed by `__attribute__((packed))` or `#pragma pack(1)`
  becomes a `@[Packed]` `lib struct`.  It was laid out unpacked, with the wrong
  member offsets.  Other packing which moves a member, like `#pragma pack(2)`
  or a packed union, is refused.
* `TEMPLATE.yml` documents the `camelcase:` option of `enums:`, no longer
  documents the non-existent `multiple:` option of `find_paths:` shell tries,
  says that `block_overloads` isn't in the default `processors:`, and that
  `build:` of `generators:` isn't run.

## 0.9.0 (2026-10-15)

### Breaking changes

* `BindgenHelper.keep_alive` only accepts objects responding to `#to_unsafe`.

### Changed

* `BindgenHelper.keep_alive` keeps objects by the address of their C++ object
  instead of their wrapper.  `.release` and `.kept_alive?` accept any wrapper of
  it, like one returned by a getter, and `.release` its pointer.  Keeping an
  object alive again keeps the first wrapper.
* `BindgenHelper.release` can be called from C++ code run by a GC finalizer,
  like a destruction callback, while the kept objects change.

## 0.8.0 (2026-10-14)

### Breaking changes

* LLVM and Clang 14 or newer are required.  Tested with 14 to 23.
* Crystal 1.8 or newer is required.
* CMake 3.12 or newer is required.
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
  containers, classes by value, references, pointers to arrays of other than
  built-in types, unknown types) is an error.  It used to emit invalid or
  layout-incompatible Crystal.
* Copying a structure which isn't trivially copyable and standard-layout is an
  error.
* `bindgen_helper.hpp` disables clang's `-Wreturn-type-c-linkage`.
* `Binding::CrystalSlice` gained a `read_only` field after `ptr` and `size`,
  and `bindgen_helper.hpp` defines the matching C++ `struct CrystalSlice`.
  Projects defining their own C++ `CrystalSlice` have to use this one.
* Wrapper classes get more methods: copy constructors become `.new(other)`,
  `operator=` becomes `#assign!` and conversion operators `#to_TYPE`.  These
  may clash with methods added to the wrappers by hand.
* The arguments of an override are named like those of the overridden method,
  which changes the names of some arguments for named-argument calls.
* A class whose first wrapped base isn't at offset 0 in C++ no longer inherits
  from it in Crystal, but converts to it with `#as_X`.
* Methods and data members using a template instantiation that is neither
  configured nor a container are ignored.

### Added

* C arrays (#76):
  * Members of copied structures become `StaticArray`s.
  * Array members of built-in types get a getter returning a `Slice`.
  * Methods taking or returning references to arrays of built-in types use
    `Slice`s.  Passing one of the wrong size raises an `ArgumentError`.
  * Pointers to arrays of built-in types, like `int (*)[4]`, become pointers
    to `StaticArray`s in arguments, results and members.
  * Array members and references to arrays of enums and copied structures
    use `Slice`s.  Those of wrapped classes use `BindgenHelper::ArrayView`,
    an `Indexable` view whose elements refer to the C++ array, and which
    copy-assigns elements through `#[]=`.
* Generic container modules (#102): `Container(T)` can be used as type
  restriction, `Container.of(T)` returns the wrapper class of an instantiation
  and `.from` builds one from any `Enumerable`.
* `#to?(T.class)` casts between wrapper classes, down to polymorphic
  sub-classes through `dynamic_cast` (#87).
* Associative containers (`type: Associative`), like `std::map`,
  `std::unordered_map` and `QMap`: The wrappers include
  `BindgenHelper::AssociativeContainer(K, V)`, which offers a `Hash`-like
  interface, and are built from a `Hash`.  The C++ method names are configured
  by `count_method`, `erase_method` and `insert_method`.
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
* `keep_alive:` in `types:` configures the methods which keep a pointer to
  their arguments, like `QStatusBar::addWidget`.  Their wrapper methods pass
  wrapped objects to `BindgenHelper.keep_alive`, so the GC doesn't collect them
  while C++ uses them, until `BindgenHelper.release` (#75).
* Copy constructors (`.new(other)`), assignment operators (`#assign!`) and
  conversion operators (`#to_bool` for `operator bool()`) are wrapped.
* Class template instantiations can be wrapped by listing them in `classes:`,
  like `"Box<int>": IntBox` (#117).  Methods using them are wrapped instead of
  skipped.  Integral non-type template arguments, like the `4` in
  `std::array<int, 4>`, are supported in instantiations and type names.
* The integration specs are parsed in the C++ standard they're built in.
* The clang tool can be built out of tree (`cmake -S clang -B build/llvm-19`),
  keeping a build directory per LLVM version.
* Logging uses Crystal's `Log` directly, the `spoved` dependency is gone.
  The output and the `--debug` and `--trace` flags are unchanged.
* GitHub Actions workflow, replacing Travis CI.  It tests LLVM 14 to 23 on
  Ubuntu, shared LLVM on Arch Linux, and Homebrew's LLVM on macOS, linked
  statically and dynamically.
* Ameba as development dependency, configured in `.ameba.yml` and run in CI.
  Installing the development dependencies needs Crystal 1.19 or newer.

### Fixed

* Overriding one overload of a C++ virtual method in Crystal hooked all
  overloads of that name, recursing endlessly in the others.  Only overloads
  accepting the C++ argument types are hooked.
* Pointers to converted types, like `std::string *`, in copied structures
  become `Void*` instead of being rejected.
* Building and running on macOS with Homebrew: LLVM, PCRE2 and the libraries
  LLVM depends on are found, the SDK's C headers are searched, `libxcselect`
  is linked for newer Clang drivers, and `tool.sh` no longer requires
  coreutils.
* Static linking against LLVM 23.
* Constructors of aggregates, unions and of types with a `from_cpp` converter
  generated C++ code which didn't compile.
* `find_path` regular expressions were compiled with the dot-all instead of the
  multi-line option on Crystal 1.8 and newer.
* The clang tool crashed when a class template was listed in `classes` (#117).
  It now reports an error.
* The clang tool no longer leaves through `exit()` to avoid a crash in Clang's
  destructors (#37).  Macros are evaluated at the end of the same parse, and one
  with unbalanced brackets no longer breaks evaluating the following ones.
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
* Constructors of classes with a private destructor are no longer wrapped.
* A class whose virtual methods were all filtered generated an empty `lib`
  struct, which Crystal rejects.
* Virtual methods declared further up than the direct bases, like
  `QWidget::resizeEvent` for `QLabel`, couldn't be overridden in Crystal.
* Overrides of virtual methods name their arguments like the overridden method,
  which Crystal warned about.
* A class inherited in Crystal from its first wrapped base even if that base
  isn't at offset 0, like a non-polymorphic base of a polymorphic class.  Its
  methods then got the wrong pointer.  The Crystal superclass is now the first
  wrapped base at offset 0.
* Anonymous types of a class renamed in `classes:` were put into a namespace
  named after the C++ class, instead of into the renamed class.
* Nested classes didn't inherit from their wrapped bases in Crystal.
* The clang tool wrote control characters other than newline and tab into
  JSON strings unescaped, like those of an evaluated string macro.
* A class inheriting from a class in another namespace that is defined later,
  like `N::C < B < N::A`, was written before its superclass, which didn't
  compile (#89).  Such classes are moved after their superclass, reopening
  their modules.
