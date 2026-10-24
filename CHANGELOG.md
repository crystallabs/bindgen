# Changelog

Notable changes to bindgen.  For releases up to 0.7.0 see the Git history.

## Unreleased

### Added

* `parent_arguments:` type rule: the names of the constructor arguments giving
  the object a parent, which owns and deletes it, in classes the `Qt`
  processor doesn't know to be parent-owned, like `QTreeWidgetItem`
  (`[parent, treeview]`), `QListWidgetItem` (`[listview]`) or `QUndoCommand`.
  The processor keeps such an object alive while it has a parent, like a
  `QObject`'s child, also in the subclasses; a name matching no object argument
  of a constructor is warned about.
* `BindgenHelper.owned_by(object, owner)` keeps an object alive while it has
  an owner, and lets it go given `nil`; the `Qt` processor's hooks call it.

* A top-level `ignore_methods:` drops methods in every class, and functions,
  by name, signature or regular expression like the type rule.
* A method declared `[[deprecated]]` is wrapped under `@[Deprecated]` unless
  `ignore_deprecated` drops it; the glue ignores `-Wdeprecated-declarations`
  for calling it.
* A virtual method's unnamed arguments take the names an override gives
  them, like `QValidator::validate(QString &, int &)` from
  `QAbstractSpinBox::validate(QString &input, int &pos)`, so a Crystal
  subclass can name them without a warning.  `Processor::Inheritance` names
  them in place before unifying the overrides.
* `Set` container kind (SPEC.md §2.6.4): `std::set<T>` and `QSet<T>` are
  wrapped as an `Enumerable(T)` with `#includes?`, `#add`/`#<<`, `#delete`,
  `#concat`, `#size` and `#empty?`, taking any `Enumerable` as argument and
  built by `Set.of(T).from(values)`.  `#each` copies the elements into a
  `BindgenSetElements` first.  `push_method` defaults to `insert`;
  `count_method` and `erase_method` name `contains` and `remove` for a
  `QSet`.
* `std::function<R (Args...)>` arguments, also through a typedef like
  `QTextDocument::ResourceProvider`, are taken as a block, or a `Proc` when
  not last or in a setter (SPEC.md §2.2.6).  The clang tool describes a function type
  with its return and parameter types (`isFunction`, format version 12);
  `Parser::Argument` turns a `std::function` into a `Kind::Function` type
  like a signal's, and `Cpp::Pass` builds the `std::function` from a lambda
  calling the `CrystalProc`, held by `bindgen_hold_proc` in memory the GC
  scans but doesn't collect, freed with the last copy of the function.  A
  method returning a `std::function` or taking a function pointer is skipped,
  a virtual method taking one isn't overridable.  `Template::ProcFromWrapper`
  calls the `Proc` named by its argument instead of always `_proc_`, and a
  lambda calling Crystal converts its result (`CppToCrystalProc::LambdaBody`).
* Type discovery (SPEC.md §2.3.7): a pointer or reference to a polymorphic
  class is wrapped in the wrapper class of the object's dynamic type, the most
  derived one the binding knows, in the results of methods, the arguments of
  callbacks and `#to?`.  `Processor::Inheritance` gives each polymorphic class
  with wrapped sub-classes a C++ `DISCOVER` function, a `BindgenTypeDiscovery`
  table in `bindgen_helper.hpp` looking the `typeid` up and walking the
  `dynamic_cast`s once for an unknown type, and the Crystal class method
  `bg_discover`, which `Crystal::Pass#from_wrapper` calls instead of
  `new(unwrap:)`.  Without RTTI nothing is discovered.  Specs expecting the
  declared class, like the `Impl` of an abstract class, see the sub-class now.

* `classes:` takes a typedef naming a class template instantiation, like
  `QMatrix3x3` for `QGenericMatrix<3, 3, float>`, wrapping the instantiation
  under the typedef's name.  The clang tool is told every class through
  `BindgenInstantiation` now, and takes a class template specialization found
  that way as an instantiation; the operators of a plain class name are also
  matched by the registered name.  The output format is unchanged.
* Wrapper identity for objects constructed from Crystal: a pointer to one
  comes back as the Crystal object which constructed it, an instance of a
  Crystal sub-class with its instance variables included.  The constructors
  call `BindgenHelper.set_crystal_object`, which stores the Crystal object in
  the `BindgenGCObject` of the allocation as a disappearing link of the GC,
  so the reference is weak; every wrapper class, polymorphic or not, gets a
  `bg_discover` reading it back (`BindgenHelper.crystal_object`).  A pointer
  to a secondary base or to a member object, and a copy, get a new wrapper.

* `ignore_methods:` entries match a C++ signature, dropping one overload:
  `operator-(const QDateTime &, const QDateTime &)`, with ` const` after the
  parentheses for a const method, spacing normalized; or a regular expression
  between slashes over the signature: `/^operator\*\(.*QVector3D/`.  A plain
  name drops every overload as before.  `Parser::Method#signature` prints the
  signature matched.

* `release:` type rule, the counterpart of `keep_alive:` for methods handing
  an object back, like `QLayout::takeAt` or `removeWidget`: the wrapper passes
  the selected object arguments, and the result when all arguments are
  selected, to `BindgenHelper.release`.  `BindgenHelper.release(nil)` does
  nothing, like `keep_alive(nil)`.

* `member_functions:` binds free functions, like `qHash`, as methods of the
  class of their first parameter, like friend operators: `Point#q_hash(seed)`.
  The `Qt` processor forwards `qHash` to `#hash(hasher)`, so value types are
  `Hash` keys and `Set` elements with `#==` from `operator==`, and a
  `toString()` without mandatory arguments to `#to_s(io)` and `#inspect(io)`.
  `Parser::Method#free_function?` marks these methods; the clang tool takes
  them as `-F`.
* Exception boundary of callbacks from C++: a Crystal override of a virtual
  method, or the block of a Qt signal, runs in `BindgenHelper.rescued`.  An
  exception it raises goes to `BindgenHelper.on_exception`, printing it with
  its backtrace to the standard error by default, and C++ receives a zero of
  the result type (`BindgenHelper.zero_value`).  Before, the exception unwound
  through the C++ frames.

* `super` works in a Crystal override of a C++ virtual method: the wrapper
  method it reaches forwards to the `Superclass` wrapper on an instance of a
  Crystal subclass, told apart from the generated classes by their
  `BindgenWrapper` annotation, as Crystal's dispatch ran the overrides of the
  subclass already.  Before, `super` re-entered the override through the
  virtual method, overflowing the stack.  The `Superclass` forwarders get
  the `keep_alive:`, `release:` and parent-ownership hooks of the wrapper
  methods, so `super` keeps what the wrapper keeps.

* Out arguments: a method taking a converted value type (`pass_by: Value` with
  `to_cpp` and `from_cpp`), like `QString`, `QByteArray`, `QVariant` or
  `std::string`, by non-const reference or by pointer is wrapped, instead of
  being dropped.  The wrapper returns the values written back with its result:
  `state, input, pos = validator.validate("42", 0)` for
  `QValidator::validate(QString &, int &)`, the value alone for a `void` method
  with one out argument.  A reference is in/out, a pointer is out-only and
  left out of the wrapper's arguments; in such a method, `int &` and `bool *`
  are out arguments too.  A Crystal override of a virtual method with out
  arguments returns the same tuple, which is written back into the C++
  references, so `QValidator` can be subclassed.  Constructors, member
  setters, signals and operators keep dropping such arguments.  See SPEC.md
  §2.2.5.

* `builtin_out_arguments:` option: a non-const reference or pointer to a
  built-in type or an enum a method writes through, like `bool *ok` or
  `int &`, is an out argument in every method, returned with the result:
  `value, ok = variant.to_int`, `year, month, day = date.get_date`.  Without
  it, as before, only next to a converted out argument.  A pointer to a byte
  or character type, or to `void`, is a buffer and stays a pointer either way.
* `out_arguments:` type rule, by the entries of `ignore_methods`: `true`
  takes every such argument of a method, buffers included, `false` none, a
  list of indices those; the rule of a base class covers the overrides.
* `declare_methods:` type rule: C++ declarations of methods the parser
  doesn't report, like the instantiations of template members
  (`QAction::menu` and `setMenu` in Qt 6, `QMutex::tryLockFor`), bound like
  any other method: `declare_methods: ["QMenu *menu() const", "void
  setMenu(QMenu *menu)"]`.  `Parser::Method.from_signature` parses them.
  `Parser::Type.parse` marks the fundamental types, like `unsigned int`, as
  built-in, as the clang tool does.
* A copied structure passed by value (`copy_structure` with `pass_by:
  Value`, like `QPoint`) taken by non-const reference or non-const pointer
  is passed as a pointer to its storage, so the method writes into it: the
  object of a wrapper class hosting the structure, `stream >> point`, or the
  Crystal `struct` of a `kind: Struct` wrapper, taken by pointer, `stream >>
  pointerof(point)`.  Such methods were dropped before.  A pointer takes
  `nil` under the `nilable:` rule.
* `containers:` kind `Optional`, for `std::optional<T>`: converted to and
  from a `T?`, the value or `nil`, like a pair to a `Tuple`.  The wrapper
  class (`Std::Optional.of(T)`) has `#has_value?`, `#to_nilable`, `#value=`
  and `.from`.  `access_method`, `push_method` and `count_method` default to
  `value`, `emplace` and `has_value` for it.
* `shadowed_by:` type rule: an overload taking the type is dropped where
  another overload takes one of the listed types in its place, like
  `QString::indexOf(QStringView)` next to `indexOf(const QString &)`, for a
  view type converted like the type it views.
* `rename:` and `nilable:` type rules, by the entries of `ignore_methods`:
  `rename: { raise: raise_ }` names a method, and its overrides in Crystal;
  `nilable: { menuBar: false, setModel: [0] }` makes a pointer result `T`
  or `T?` regardless of `nilable_results`, and pointer arguments accept
  `nil`.

### Changed

* Having a parent and being passed to `BindgenHelper.keep_alive` are two
  reasons to keep an object alive, and it's collectable once neither holds:
  `parent = nil` ends the parent's reason only, so an object a `keep_alive:`
  rule keeps, like a model set on a view or a graphics item in a scene, stays
  kept.  Before, the table of kept objects held one entry per object, and
  `parent = nil` let it go, which deleted the model under the view once
  Crystal dropped it.  `release`, by hand or by a `release:` rule, still ends
  both: a method handing an object back, like `takeTopLevelItem`, ends its
  ownership too.
* `BindgenHelper.keep_alive` and `owned_by` don't keep an object C++ created,
  which Crystal only wraps: its wrapper keeps nothing C++ uses, and as nothing
  told of its deletion, the stale entry kept a wrapper of freed memory, and
  blocked keeping a new object at the same address.  `bindgen_kept_key`
  returns null for such an object, off the GC heap or allocated uncollectable
  by the `operator new` of libgccpp.
* Of two methods taking the same Crystal arguments, the one with more C++
  arguments stays, instead of the one with fewer: the variant of a method
  split at a default argument whose further arguments have exposed defaults,
  like `getText(..., bool *ok = nullptr)` next to `getText(...)`, takes the
  same calls through the defaults and more.  Before, such a variant was
  dropped, so `ok` could only be passed together with the argument after it,
  or not at all.
* `BindgenHelper.keep_alive`, `release`, `kept_alive?` and the destroyed hook
  key an object by the start of its GC allocation (`bindgen_kept_key` in
  `bindgen_helper.hpp`), by its address off the GC heap or without C++ glue.
  A wrapper of a secondary base, like `widget.as_paint_device`, kept alive
  wasn't found by `release(widget)` or by the hook of its deletion.

### Fixed

* A class given a Crystal name nested under another wrapped class, like
  `"QCborStreamReader::StringResult<QString>": CborStreamReader::StringResult`,
  and built before that class, made the sanity check report the enums of the
  outer class unreachable: the namespace created for the nested name stayed
  next to the class of the same name.  The class takes the namespace's place
  now, with its nodes.
* An instance of a Crystal subclass overriding a virtual method was never
  collected: the `Proc` of the override, stored in the C++ object, captured
  the Crystal object, which refers to the C++ object, and the GC doesn't
  finalize an object reachable from itself through another ("GC Warning:
  Finalization cycle involving").  The virtual method of the C++ subclass now
  looks the Crystal object up, like the type discovery does, and passes it to
  the `Proc`, which captures nothing (SPEC.md §2.3.4).  Such an instance is
  collected once nothing holds it, like any other object; a `depends_on:`
  dependency stores the Crystal object of the dependency, so the overrides of
  a dependency's class keep working while the dependent object lives.  As Qt
  refers to the sender of a connected signal, from memory the GC scans but
  never collects (Qt allocates through the `operator new` of libgccpp), so
  the C++ object lives on anyway, the `Qt` processor's connection methods pass
  the sender to `BindgenHelper.keep_alive` (SPEC.md §Q.1.4): before, the
  closure kept such a sender.
* A Crystal subclass not overriding a virtual method got a jumptable entry
  for it anyway once the method had been called through the wrapper class
  earlier in the program: the compiler copies a method expanding `@type`,
  which the `super` forwarding of 0.15.0 made every wrapped virtual method,
  into the subclasses, and the constructor's hook took the copy for an
  override.  C++ then called the method through Crystal, and the closure of
  the entry, referring to the Crystal object from the C++ object, kept both
  from ever being collected.  The forwarding methods carry the
  `BindgenWrapper` annotation now, and the hook skips them.
* A Crystal override of a virtual method returning an enum, like
  `QValidator::validate`, didn't compile: the `Proc` passing its result to
  C++ called `to_unsafe` on the enum.
* The `Qt` processor connects signals with a context object and a connection
  type, which the context-less functor overload of `QObject::connect` it used
  lacks: that one calls the block on the emitting thread, as a direct
  connection, so `thread.on_started { }` ran on the Qt thread, and a thread may
  not run Crystal code.  The context is `QCoreApplication::instance()`, the
  sender while there is no application, so an automatic connection from
  another thread is queued to the main thread.  The connection methods take
  the type: `on_finished(Qt::ConnectionType::QueuedConnection) { }`, after the
  type arguments of an overloaded signal, and default to `Qt::AutoConnection`.
  The configuration must wrap the `Qt::ConnectionType` enum.
* The block of a signal connection method, and any `Proc` a wrapper takes,
  types a pointer argument defaulting to `nullptr` as nilable, like the
  conversion of the argument did: `on_destroyed { |object| }` didn't compile,
  as the block was a `Proc(Object, Void)` called with an `Object?`.
* `BlockOverloads` tells the overloads of a block-taking method apart by their
  other arguments too, so the connection methods above still get their type
  arguments; and the Crystal formatter exposes the default of an optional
  argument before a block: `def f(x = 1, &)`.

## 0.15.0 (2026-10-23)

### Added

* `depends_on:` applies to member methods, like `QTextStream::setDevice` or
  `QPainter::begin`: the call replaces the dependencies of the object by its
  selected arguments, so the GC destroys the object before them, and they're
  collectable again with it or after a later call.  Unlike `keep_alive:`,
  nothing needs releasing.  The method does nothing on an object C++ created.
  Static methods, and the methods of copied, aggregate, union and `final`
  classes, are ignored with a warning.
* The `Qt` processor keeps an object given a parent alive, as the parent owns
  it, in the classes deriving from `QObject`, `QGraphicsItem` or
  `QGraphicsLayoutItem`: a constructor with a `parent` argument given one, and
  `setParent`, `setParentItem` and `setParentLayoutItem` given an object, pass
  `self` to `BindgenHelper.keep_alive`.  Given `nil`, the setters release it.
  Their argument is nilable now.  Before, `Qt::Label.new("x", window)` was
  collected once Crystal dropped it, and taken out of the window.  As a parent
  deleting its children releases them since 0.14.0, this doesn't leak.
* `Call::HookableBody#add_post_hook` adds a hook after the one set already.
  `VirtualOverride` uses it for the jump table, after the hook above, and set
  none before if a constructor had a post-hook.

### Changed

* `CrystalGCCleanupWrapper<T>` keeps `bindgen_dependencies` and
  `bindgen_destroyed` in its new first base `BindgenGCObject`, at the start of
  the allocation for every `T`, so the glue of a method finds them by
  `GC_base`, see `bindgen_gc_object`.  The `T` of a wrapper constructed from
  Crystal is now never at its start, also for a dynamic `T`: code assuming that
  the `T *` is the address of the allocation needs `GC_base`.
* The `keep_alive:` and `depends_on:` rules of a class apply to the methods its
  subclasses re-declare, like an override of a setter: `QTreeView::setModel`
  keeps its model as `QAbstractItemView::setModel` is configured to.  Before,
  only the methods of the class itself, and those bound from it into
  subclasses, followed its rules, so an override escaped them.
* An override of a virtual method takes the default values of the method it
  overrides where it has none, and is named like it, also when that one comes
  from a base other than the Crystal superclass, or from a further ancestor:
  `QGraphicsTextItem#paint(painter, option, widget : Widget? = nil)` like the
  pure `QGraphicsItem::paint`, which it implements.  Before, only the bases
  through the Crystal superclass were searched, so its `widget` stayed
  mandatory, and Crystal rejected the class for not implementing the abstract
  method.

### Fixed

* A post-hook of a wrapper method returning `Void` no longer assigns the
  result, which Crystal rejects.

## 0.14.0 (2026-10-23)

### Changed

* C++ deleting an object constructed from Crystal, like a Qt parent deleting
  its children, releases it from `keep_alive`: the destructor of
  `CrystalGCCleanupWrapper` tells the generated module, which registered
  `BindgenHelper.release` with `bindgen_add_destroyed_hook` of
  `bindgen_helper.hpp`.  Before, nothing was released automatically, and the
  program had to release an object C++ deleted, like from `QObject::destroyed`.
  An object C++ created, which Crystal only wraps, still needs that.  A binding
  without a `cpp` generator leaves the registration out.
* The releases a GC finalizer asks for while the table of kept objects changes
  are queued in memory of `malloc`, grown as needed.  The queue held 64, and
  further objects stayed kept alive.

## 0.13.3 (2026-10-19)

### Added

* A `keep_alive:` or `depends_on:` pattern matching no method of its class is
  warned about, so a misspelt method name, or one `ignore_methods` drops, isn't
  silent.

## 0.13.2 (2026-10-19)

### Fixed

* `delete` on a wrapped object, by C++ code owning it like a Qt parent, runs
  its destructor but leaves the memory to the GC, and the finalizer skips an
  object C++ destroyed.  Before, when the owner and the object were collected
  together and the owner was finalized first, the queued finalizer of the
  object ran on freed memory and crashed.

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
