# Changelog

Notable changes to bindgen.  For releases up to 0.7.0 see the Git history.

## 0.13.1 (2026-10-19)

### Fixed

* An alias template specialization like `couple<std::string, int>` is named by
  the type it aliases with the arguments as written, `std::pair<std::string,
  int>`, with Clang before 20 too.  Those substitute the canonical arguments,
  which named `std::basic_string<char, ...>`, a type without rules.

* `depends_on:` applies to the copy constructor too: a copy depends on the
  object it copies, so the GC destroys it first, and in turn before what the
  original depends on.  Copies were destroyed in any order before.

## 0.13.0 (2026-10-19)

### Added

* `depends_on:` of a type names the constructors whose object refers to some
  of its arguments from memory the GC doesn't scan, and uses them when
  destroyed, like an iterator unregistering from its container.  The C++ glue
  stores these arguments in the new object, so the GC keeps them alive as long
  as it, and destroys them only after it.  Same format as `keep_alive:`.
* The variables `find_paths` sets, like the version of a version check, can
  be tested by conditions: `if_QT_VERSION_newer_or_6.6:`.  The tool reads the
  configuration again once the paths were found.
* `find_paths` determines the version of a path the user preset, when its
  version check stores one: `QMAKE=/opt/qt/bin/qmake6` sets `QT_VERSION` too.
* The parser looks through alias template specializations, like Qt 6's
  `QPair<T1, T2>` for `std::pair<T1, T2>`, so the type rules and containers of
  the aliased template apply.
* A non-member operator taking the class by value, like Qt 6.4's
  `friend bool operator==(QDate lhs, QDate rhs)`, is wrapped like one taking
  it by reference.  A deleted operator is skipped.

## 0.12.0 (2026-10-19)

### Added

* A container instantiation listed in `classes:`, like
  `"QList<QString>": StringList`, is wrapped from its parsed methods and bases
  under that name, on top of the container interface.  This wraps the
  methods Qt keeps in `QListSpecialMethods<QString>`, when that specialization
  is listed too.
* A class deriving from a container instantiation, like
  `QPolygon : public QList<QPoint>`, inherits the container wrapper, so it is
  an `Indexable` and is accepted where C++ expects the container.  The
  `inheritance` processor must run after `instantiate_containers` for this;
  the default pipeline and `TEMPLATE.yml` do.
* `auto_container_instantiation` also instantiates the containers found in
  base classes and in `classes:`.
* The parser looks through the typedefs a class template instantiation
  declares, like `QList<QString>::value_type`, and names the template
  arguments of an instantiation listed in `classes:` as written there, like
  `std::string` instead of `std::basic_string<char, ...>`.

* `filter_methods` drops the methods using a type nested in a template
  instantiation, like `QList<QString>::iterator`, unless it has rules.  The
  methods `instantiate_containers` and `inheritance` add are filtered by the
  same rules, so `filter_methods` needs to run only once.
* The `Impl` class of an abstract class deriving from another abstract class
  gets the overloads a default argument splits an inherited pure method into.
* `nilable_results: true` returns `nil` for a null pointer to a wrapped
  class, so such results are `T?`, instead of a wrapper of the null pointer.
  Not for the argument of a callback, which a Crystal override takes as
  declared, nor for container elements, pair members and `#as_X` casts.
* Pair types, like `std::pair` and `QPair`, are containers of `type: Pair`,
  converted to and from a Crystal `Tuple`, also inside other containers.
* `ignore_deprecated: true` drops the methods and functions declared
  `[[deprecated]]`, overload by overload, in `filter_methods`.  The parser
  reports the attribute as `isDeprecated`.

### Fixed

* The parser no longer crashes on a `QFlags<E>` typedef nothing instantiates,
  like `QMessageBox::Options` of an `enum class`.
* A callback, like a Qt signal or a virtual method override, receives a
  built-in `kind: Struct` type passed by value or by reference, like the
  `CrystalVariant` behind a `const QVariant &`, by pointer, as copied
  structures already were: the C
  ABI passes a structure larger than 16 bytes indirectly, which a Crystal
  `Proc` taking it by value read as garbage.  `bindgen_address` of
  `bindgen_helper.hpp` takes the address of a converted temporary.
* A typedef without rules or an alias of its own, like `QFileInfoList`, is
  looked through to the type it names, `QList<QFileInfo>`: the parser reports
  the canonical type, so nested typedefs resolve too, and the type database
  resolves it like an alias, also for a `const T &` argument.
* `auto_container_instantiation` instantiates the containers nested in
  template arguments too, like the pairs of a `QList<QPair<...>>`, and so
  does `instantiate_containers` for the configured `instantiations`.
* The arguments of virtual methods keep what their typedef names when they
  are unified across the class hierarchy, so a `const QModelIndexList &` of
  `QAbstractItemModel::mimeData` is looked through like elsewhere.
* The overload a default argument Crystal can't express splits off a pure
  virtual method is concrete, calling C++ with the default, which dispatches
  to the override: a Crystal subclass implements the full overload only,
  like `row_count(parent)` of a model.
* A default-argument overload copied from a base class stays one, so no
  forwarder calling a non-existent C++ overload, like `columnCount()` of
  `QStringListModel`, is generated.
* A method a base class overrides privately, like `QAbstractListModel::parent`,
  is wrapped through the base it is public in, and the private override is
  seen by `virtual_override` through intermediate bases, so a subclass gets no
  forwarder calling the private method.  The `Impl` class of such a base
  no longer lacks the method.
* A nilable wrapper argument, like `parent : Widget? = nil`, is converted
  explicitly, so a variable of the union type can be passed: Crystal
  accepts `nil` or an object for a pointer parameter, but not their union.
* A C++ method named like a reserved Crystal method, `initialize` or
  `finalize`, is wrapped as `#cpp_initialize`, instead of breaking the
  wrapper's constructor.
* `None` and `All` enumerators of a flags enum are left to Crystal's
  `@[Flags]`, which defines them, when their values agree; otherwise they
  are renamed `CppNone` and `CppAll`, instead of failing the sanity check.
* A class with a pure virtual method `filter_methods` drops, like one taking
  an ignored type, is no longer sub-classed in C++ (which left the subclass
  abstract and uncompilable); it is wrapped without Crystal overrides, with
  a warning.
* Enums are named by their global path in `lib Binding`, so a nested enum
  of a class wrapped under its C++ name, like `QMutex::RecursionMode` of
  `QMutex: QMutex`, isn't shadowed by the lib's alias of the class.
* The C++ wrapper of a method of an anonymous struct, like the implicit
  `operator=` of `QMetaObject::d`, names the struct by its typedef.
* `instance_variables` rules are keyed by the C++ name of the class, like
  the other type rules; the Crystal name still works.
* A base method re-exported by a using-declaration, like `lock` of Qt 5's
  `QRecursiveMutex : private QMutex`, is wrapped.
* `std::nullptr_t` is ignored by default, dropping the `nullptr` overloads.
* A Crystal override returning the nilable result type of `nilable_results`
  passes `nil` to C++ as a null pointer.
* An abstract class keeps its implicit default constructor, which
  `std::is_default_constructible` denies, so a Crystal subclass of
  `QItemEditorCreatorBase` constructs.
* A method whose Crystal name and argument types equal another's, like the
  std-style alias `try_lock` of `tryLock`, is dropped instead of generating
  an ambiguous overload; so is one whose arguments are a prefix of another's
  remaining defaults, like `try_acquire()` next to `tryAcquire(int n = 1)`,
  which Crystal would replace rather than overload.
* The glue's `Mutex` is qualified as `::Mutex`, so a wrapped class may be
  named `Mutex`.
* `#to?` to an abstract class wraps the cast in its `Impl` class instead of
  instantiating the abstract class.
* A typedef of a typedef with rules of its own, like `QElapsedTimer::Duration`
  of `std::chrono::nanoseconds`, resolves to that typedef rather than to the
  canonical type.
* A container of an ignored type, like a `QMap<QFont::Tag, quint32>` of a
  dropped method, is no longer instantiated.
* A pointer argument defaulting to `nullptr`, like `bool *ok = nullptr`,
  defaults to `nil` instead of `true`.
* A deduced `auto` return type is named by the deduced type, fully
  qualified.
* An operator Crystal can't name, like `operator->`, is dropped by
  `filter_methods` instead of aborting.
* A parameter named like a Crystal keyword, like `self`, is renamed.
* A templated friend operator, like `QDataStream`'s, is skipped by the
  parser instead of dragging template parameters into the binding.
* A copied structure wrapped as a Crystal `struct` (`kind: Struct`) gets
  property methods for its public fields.
* Type rules shared through a YAML anchor are copied per type, as bindgen
  keeps per-type state in them.
* A `const void *` is a `Void*`, no longer a `Void**`: the `void *` rule
  merged into the `void` rules through the decayed type.
* The result of a C++ operator is converted as a whole: a `from_cpp` rule
  like `(%.count())` applied to `a - b` gave `a - (b).count()`, which
  broke `QDateTime::operator-` returning `std::chrono::milliseconds`.
* A virtual operator, like `QTableWidgetItem::operator<`, no longer aborts
  `virtual_override` with "Unexpected operator".  It is wrapped and can be
  overridden from Crystal; the override can't call the C++ implementation
  through `#superclass`.
* The parser names a base class by its type, so a class template instantiation
  base keeps its arguments: `QList<QPoint>` instead of `QList`.
* The Crystal generator writes a class after the types its included modules
  name, like the enum a container wrapper is of, not only after its
  superclass.  The order of the `enums` and `instantiate_containers`
  processors no longer matters for this.
* A path lookup prefers a node of all platforms over a platform-specific one of
  the same name, like a container class over its C++ typedef.

## 0.11.1 (2026-10-18)

### Fixed

* A virtual method overridden with a covariant return type, like
  `Derived *clone()` overriding `Base *clone()`, is no longer taken for an
  overload, which copied the base method into the subclass and made both
  ambiguous.
* A default argument value above `Int32::MAX`, like an enumerator `0xffffffff`,
  no longer overflows when generating the Crystal wrapper.
* Qt signals listed in `ignore_methods`, or removed otherwise before the `qt`
  processor runs, get no `on_X` connection method.
* A macro which isn't an expression, like `__attribute__((used)) inline`, is
  skipped instead of aborting with "Can't convert nil of Nil to auto".
* `qsizetype` maps to the signed `Int64` (`Int32` on 32-bit platforms) instead
  of `LibC::SizeT`.

## 0.11.0 (2026-10-18)

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
