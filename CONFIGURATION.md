# Configuration reference

Bindgen is configured by a YAML file, which is passed to `tool.sh`.  This
document describes every key of that file.

`TEMPLATE.yml` is the same configuration as a commented example: Copy it to
start a new binding.  The general features of the YAML files, conditions
(`if_os_is_darwin:`) and dependencies (`<<: other.yml`), are described in the
README under [Advanced configuration features](README.md#advanced-configuration-features).
What each processor does is described under [Processors](README.md#processors).

# Table of Contents

<!--ts-->
   * [Templated strings](#templated-strings)
   * [module](#module)
   * [cookbook](#cookbook)
   * [library](#library)
   * [processors](#processors)
   * [generators](#generators)
   * [find_paths](#find_paths)
      * [Searching](#searching)
      * [Checks](#checks)
      * [Version check](#version-check)
      * [Lists](#lists)
   * [classes](#classes)
   * [enums](#enums)
   * [macros](#macros)
   * [functions](#functions)
   * [member_functions](#member_functions)
      * [Function classes](#function-classes)
   * [containers](#containers)
   * [parser](#parser)
   * [types](#types)
      * [alias_for](#alias_for)
      * [ignore](#ignore)
      * [kind](#kind)
      * [crystal_type](#crystal_type)
      * [cpp_type](#cpp_type)
      * [binding_type](#binding_type)
      * [from_cpp](#from_cpp)
      * [to_cpp](#to_cpp)
      * [converter](#converter)
      * [to_crystal](#to_crystal)
      * [from_crystal](#from_crystal)
      * [pass_by](#pass_by)
      * [wrapper_pass_by](#wrapper_pass_by)
      * [sub_class](#sub_class)
      * [copy_structure](#copy_structure)
      * [instance_variables](#instance_variables)
      * [builtin](#builtin)
      * [generate_wrapper](#generate_wrapper)
      * [generate_binding](#generate_binding)
      * [generate_superclass](#generate_superclass)
      * [ignore_methods](#ignore_methods)
      * [declare_methods](#declare_methods)
      * [shadowed_by](#shadowed_by)
      * [rename](#rename)
      * [nilable](#nilable)
      * [superclass_ignore_methods](#superclass_ignore_methods)
      * [keep_alive](#keep_alive)
      * [release](#release)
      * [depends_on](#depends_on)

<!--te-->

## Templated strings

Some values are *templated* strings.  In them:

* `%` is replaced by a value which depends on the key, like the project root.
  Each key below says what it is.
* `{NAME}` is replaced by the environment variable `NAME`.
* `{NAME|fallback}` is replaced by `NAME`, or by `fallback` if `NAME` isn't
  set.  The fallback may be `%`: `{LIBRARY_PATH|%}`.

Variables found by [`find_paths`](#find_paths) are environment variables too,
so templated strings and conditions can use them.

## `module`

**Mandatory.**  The Crystal module all generated code is put into.

```yaml
module: MyStuff
```

## `cookbook`

How values are allocated and converted in the generated C++ code.  Defaults
to `boehmgc-cpp`.

| Name | Aliases | Use for |
|------|---------|---------|
| `boehmgc-cpp` | `cpp`, `cxx`, `c++`, `boehmgc-cxx`, `boehmgc-c++` | C++ libraries.  Objects created from Crystal are allocated by the Boehm GC and destructed when collected. |
| `boehmgc-c` | `c` | C libraries.  Objects are freed by the Crystal wrapper's `#finalize`. |
| `bare-cpp` | `bare-cxx`, `bare-c++` | C++ with plain `new`.  Nothing is ever freed. |
| `bare-c` | | C with plain `malloc`.  Nothing is ever freed. |

With `boehmgc-cpp`, add `-lgccpp` to [`library`](#library).

## `library`

The `ldflags` of the `@[Link]` annotation of the generated `lib Binding`.
Templated: `%` is the project root, relative to the generated Crystal file.

```yaml
library: "%/ext/binding.a -lstdc++ -lgccpp -lMyLib"
```

`-lgccpp` is required when wrapping C++ classes with the `boehmgc-cpp`
cookbook.  Without it, linking fails with an undefined reference to
`GC_throw_bad_alloc()`.

## `ignore_deprecated`

Whether the `filter_methods` processor drops the methods and functions
declared `[[deprecated]]`.  Defaults to `false`.

```yaml
ignore_deprecated: true
```

Unlike `ignore_methods` of a type rule, this needs no signature to drop
exactly the deprecated overloads.  Qt declares its deprecated API
with `QT_DEPRECATED_VERSION_X`, which hides the API deprecated before
`QT_DISABLE_DEPRECATED_BEFORE` and marks the rest `[[deprecated]]`, so set
this instead of listing them.  Left `false`, the deprecated methods are
wrapped under `@[Deprecated]`, so the Crystal compiler warns about their
uses.  The C++ glue ignores `-Wdeprecated-declarations` for its own calls of
them (`bindgen_helper.hpp`).

## `ignore_methods`

Methods to drop in every class, and functions, by name, by C++ signature or
by a regular expression between slashes, like the
[`ignore_methods`](#ignore_methods-1) of a type rule.  Requires the
`filter_methods` processor.

```yaml
ignore_methods:
  - d_func # Every class' private data accessor
  - "/^qt_/"
```

## `nilable_results`

Whether a method returning a pointer to a wrapped class returns `nil` for a
null pointer, so its result type is `T?`.  Defaults to `false`, in which case
a wrapper of the null pointer is returned, and using it crashes.  C++ APIs
like Qt return null pointers routinely (`parentWidget()`, `currentItem()`), so
set this for them; references are never nilable.

```yaml
nilable_results: true
```

## `processors`

The processor pipeline, run in the order given.  Defaults to:

```yaml
processors:
  # Graph-refining processors:
  - default_constructor
  - function_class
  - inheritance
  - copy_structs
  - macros
  - functions
  - instance_properties
  - operators
  - filter_methods
  - extern_c
  - instantiate_containers
  - enums
  # Preliminary generation processors:
  - crystal_wrapper
  - virtual_override
  - cpp_wrapper
  - crystal_binding
  - sanity_check
```

`TEMPLATE.yml` adds `block_overloads` after `crystal_wrapper`, which is
recommended but not in the default.  Further processors are
`auto_container_instantiation` (before `instantiate_containers`), `qt` and
`dump_graph`.  See [Processors](README.md#processors) for all of them and the
order they need.

## `generators`

**Mandatory.**  The generators writing the output, by name: `cpp` writes the
C++ wrapper, `crystal` the Crystal bindings and wrappers.  Both take the same
keys:

| Key | Description |
|-----|-------------|
| `output` | **Mandatory.**  The output file.  Templated, with environment variables only.  For `cpp`, a `%` in it writes one file per class, `%` being the class name. |
| `preamble` | Text written at the start of each output file.  The C++ one has to include `bindgen_helper.hpp`. |
| `build` | A command to build the output, run in the output's directory.  **Not run** by the current version of bindgen: Build the C++ code yourself, e.g. from `tool.sh`'s caller or a Makefile. |

```yaml
generators:
  cpp:
    output: ext/my_bindings.cpp
    preamble: |-
      #include "bindgen_helper.hpp"
  crystal:
    output: src/my_lib/binding.cr
```

## `find_paths`

Finds paths to dependencies, like header directories and tools, and puts them
into environment variables.  Optional.

Each key is the name of the environment variable to set.  The searches run in
the order they are written, so later ones can use the variables set by earlier
ones.  If the variable is already set and isn't empty, its search is skipped:
Users can point to non-standard installations that way.  The version of such
a preset path is still determined, if its [version check](#version-check)
stores one in a variable.

The configuration is read again once the paths were found, so the conditions
outside this section can test them, like `if_QT_VERSION_newer_or_6.6:` with
the variable a [version check](#version-check) sets.  The conditions inside
this section only see the variables set before the search.

Regular expressions in this section are case-sensitive and multi-line (`^`
matches at the start of each line).

### Searching

| Key | Description |
|-----|-------------|
| `kind` | What is searched for: `Directory` (default), `File` or `Executable`. |
| `optional` | If `true`, not finding a path isn't an error, and the variable stays unset.  Defaults to `false`. |
| `error_message` | Shown if nothing was found, e.g. what to install.  Shown for optional paths too. |
| `try` | **Mandatory.**  The candidates to try, in order.  See below. |
| `search_paths` | Directories relative `try` paths are searched in.  Entries are split on `:` (`;` on Windows) and may use environment variables.  Defaults to `PATH` for `kind: Executable`, to nothing otherwise. |
| `checks` | Checks a candidate has to pass, see [Checks](#checks). |
| `version` | A version check, see [Version check](#version-check). |
| `list` | Accept all matching candidates, see [Lists](#lists).  Defaults to `false`. |

An element of `try` is either a path or a command:

* A string is a path.  It may contain glob patterns like `*` and `**`.  `%` is
  the project root.
* `shell:` runs a command, which has to exit successfully.  Its standard
  output is the candidate; standard error is shown to the user.  `%` is the
  project root, and environment variables set before are available.
  * `regex:` picks the path out of the output: the first capture group, or
    the whole match.  An empty match counts as no match.  Without `regex`, the
    first line of the output is the candidate.

```yaml
find_paths:
  MYLIB_INCLUDE:
    try:
      - /usr/include/mylib*
      - shell: pkg-config --cflags mylib
        regex: "-I([^ ]+)"
    error_message: Please install MyLib: http://example.com/
```

### Checks

All checks of `checks:` have to pass for a candidate to be accepted.

* `path:` checks that a path exists below the candidate.  Only applied if the
  searched `kind` is `Directory`.
  * `kind:` the kind of that path: `File` (default), `Directory` or
    `Executable`.
  * `contains:` a string the file has to contain.
  * `regex:` if `true`, `contains` is a regular expression.  Defaults to
    `false`.
* `shell:` runs a command, `%` being the candidate.  The candidate passes if
  it exits successfully.  Standard output is hidden, standard error is shown.
* `any_of:` a list of checks, of which one has to pass.

```yaml
    checks:
      - path: mylib_version.h
        contains: '#define MYLIB_VERSION "1\.[123]'
        regex: true
      - any_of:
        - path: either_this.h
        - path: or_this.h
```

### Version check

`version:` compares the version of each candidate, and picks the best one.

| Key | Description |
|-----|-------------|
| `min` | The lowest version accepted.  Optional. |
| `max` | The highest version accepted.  Optional. |
| `prefer` | `Highest` (default) or `Lowest`. |
| `regex` | Takes the version out of the candidate's path, from its first capture group.  Defaults to the Debian-style suffix `-([0-9.]+)$`, as in `llvm-config-18`. |
| `command` | Runs a command, `%` being the candidate, and applies `regex` to its output instead.  It has to exit successfully.  Be careful: This runs commands found on the user's system. |
| `fallback` | What to do with candidates without a version: `Fail` (default) rejects them, `Accept` accepts them, `Prefer` prefers them over versioned ones. |
| `variable` | An environment variable set to the version of the picked candidate.  Not set if none was picked.  Set to the version of a preset path too, without checking the range, unless it is already set. |

```yaml
  LLVM_CONFIG:
    kind: Executable
    try: [ llvm-config*, llvm-config ]
    version:
      min: "14.0"
      command: "% --version"
      regex: "^([0-9.]+)"
      fallback: Accept
      variable: LLVM_VERSION
```

### Lists

`list: true` accepts all matching candidates instead of the first one, joined
by `:` (`;` on Windows).  Such a list can be used as `search_paths` of a later
search.  With a version check, the best candidate is first.

`list:` can also be a mapping to format the list:

* `template:` **Mandatory.**  The template of each element, `%` being the
  element.
* `separator:` put between the elements.  Defaults to the platform's path
  separator.

```yaml
  MYLIB_LIBRARY_FLAGS:
    try: [ "/usr/lib/mylib*" ]
    list:
      template: "-L%"
      separator: " "
```

## `classes`

The C++ classes to wrap, mapped to the name of their Crystal class.

```yaml
classes:
  CppClassName: CrystalClassName
  MayBeEqual: MayBeEqual
  "ns::Widget": Widget
```

Instantiations of class templates are wrapped like classes.  Type arguments
and integral arguments are supported; default arguments can be left out.
Methods using a configured instantiation are wrapped, those using another
instantiation which is not a container are skipped.

```yaml
classes:
  "scoped_refptr<nu::MenuBar>": MenuBarRef
  "std::array<int, 4>": IntArray4
  QMatrix3x3: Matrix3x3 # typedef QGenericMatrix<3, 3, float> QMatrix3x3;
  "QCborStreamReader::StringResult<QString>": CborStringResult
```

A typedef naming an instantiation is configured by the typedef's name, which
the wrapped methods then show.  An instantiation of a member class template
is configured by its qualified name.

Containers like `std::vector` are configured in [`containers`](#containers)
instead.

## `enums`

The C++ enums to copy, mapped to the path of the Crystal enum.  The enum can
be put into a wrapped class.

```yaml
enums:
  CppEnumName: Crystal::Enum::Name
```

Or as a mapping:

| Key | Description |
|-----|-------------|
| `destination` | **Mandatory.**  The path of the Crystal enum. |
| `prefix` | Removes a common prefix from the constants.  `true` detects the prefix, a string is the prefix to remove.  Constants not starting with it are left alone.  Defaults to `false`. |
| `flags` | `true` makes it a `@[Flags]` enum, `false` a plain one.  If left out, it's a flags enum if the C++ code uses it in a `QFlags<E>`. |
| `camelcase` | Camel-cases constants which aren't already: `COLOR_RED` becomes `ColorRed`.  If `false`, they are only capitalized.  Defaults to `true`. |

```yaml
enums:
  Qt::AlignmentFlag:
    destination: Qt::Alignment
    prefix: Align
    flags: true
```

## `macros`

Copies macros (`#define`s) as enums or constants.  Requires the `macros`
processor.

Each key is a regular expression which has to match the whole name of the
macro.  The rules are tried in order, the first matching one is used.

| Key | Description |
|-----|-------------|
| `map_as` | **Mandatory.**  `Enum` or `Constant`. |
| `destination` | **Mandatory.**  For `Enum`, the path of the enum.  For `Constant`, the class or module the constants are put into. |
| `name` | The name of the enum constant or constant.  `\\1` is the first capture group, and so on.  Defaults to the first capture group. |
| `type` | The C++ type.  For `Enum`, the enum's type; defaults to `int`.  For `Constant`, forces the type of all constants; by default it's deduced for each. |
| `flags` | For `Enum`, makes it a `@[Flags]` enum.  Defaults to `false`. |

```yaml
macros:
  "FOO_BAR_(.*)":
    map_as: Enum
    destination: Foo::Bar
```

Macros taking arguments are skipped.  See [Macros](README.md#macros) for which
values can be copied.

## `functions`

Wraps functions outside of classes: C functions and namespaced C++ functions.
Requires the `functions` processor, and `function_class` for `class:`.

Each key is a regular expression which has to match the qualified name of the
function: `foo` for `void foo();`, `foo::bar` for
`namespace foo { void bar(); }`.  The bare name is tried first, so `bar` also
matches `foo::bar`, and `(.*)` doesn't capture the namespace.  If several keys
match a function, the first one is used.

The value is the destination, or a mapping:

| Key | Description |
|-----|-------------|
| `destination` | **Mandatory.**  The module or class the functions are put into.  With `class:`, the name of the class. |
| `name` | The name of the method.  `\\1` is the first capture group, and so on.  Defaults to the first capture group, or the whole name if there is none.  Without `class:`, it can nest further: `"\\1::\\2"`. |
| `crystalize_names` | Rewrites getter and setter names: `setTheThing` becomes `the_thing=` instead of `set_the_thing`.  Defaults to `true` with `class:`, to `false` otherwise. |
| `class` | Wraps the functions as a class, see below. |

```yaml
functions:
  "net_(.*)": Util::Net # Short for { destination: Util::Net }
  "string_(.*)":
    name: "string_\\1"
    destination: Util::StringBuffer
```

### Function classes

`class:` turns an object-oriented C API into a Crystal class.  Functions
taking a pointer to the structure as first argument become instance methods,
the others class methods.

| Key | Description |
|-----|-------------|
| `structure` | **Mandatory.**  The C structure the functions work on. |
| `constructors` | **Mandatory.**  The functions returning a pointer to a new structure.  Namespaced functions can be given by their qualified or bare name. |
| `destructor` | The function freeing the structure, called by `#finalize`. |
| `inherit_from` | The Crystal class to inherit from, if the C library has a notion of inheritance and the base is wrapped too. |

```yaml
functions:
  "string_(.*)":
    destination: StringBuffer
    class:
      structure: string_buffer
      constructors: [ string_new_empty, string_new_from_string ]
      destructor: string_free
```

## `member_functions`

Free functions bound as methods of the class of their first parameter, like
friend operators are: the parameter, taken by value or reference, becomes
`self`, and the method is const if it is.  The function may be a friend or
declared outside the class, and only the wrapped classes get it.  Defaults to
none.

```yaml
member_functions: [qHash]
```

With `qHash`, the `qt` processor forwards the method to `#hash`, see
[`Qt`](README.md#qt).

## `containers`

Container classes (C++ templates) to wrap.  Requires the
`instantiate_containers` processor.

Each container class gets a generic Crystal module, e.g. `QList(T)`, which its
instantiations include.  It can be used in type restrictions.  `.of` returns
the wrapper class of an instantiation, and `.from` builds one from any
`Enumerable`: `QList.of(Int32).from([1, 2, 3])`.

| Key | Description |
|-----|-------------|
| `class` | **Mandatory.**  The C++ class template. |
| `type` | **Mandatory.**  `Sequential` (like `std::vector`, wrapped as an `Indexable`), `Associative` (like `std::map`, with a `Hash`-like interface), `Pair` (like `std::pair` and `QPair`, converted to and from a `Tuple`), `Optional` (like `std::optional`, converted to and from a `T?`; `access_method`, `push_method` and `count_method` default to `value`, `emplace` and `has_value`) or `Set` (like `std::set` and `QSet`, an `Enumerable` with `#includes?`, `#<<` and `#delete`; `push_method` defaults to `insert`, `count_method` and `erase_method` as for an associative container). |
| `instantiations` | The instantiations to wrap, each a list of the template arguments: `[ "int" ]` for a sequential, `[ "std::string", "int" ]` for an associative container.  May be left out when using the `auto_container_instantiation` processor. |
| `access_method` | Returns an element.  Defaults to `at`. |
| `size_method` | Returns the number of elements.  Defaults to `size`. |
| `push_method` | Appends an element.  Defaults to `push_back`. |
| `count_method` | Associative and set: Returns the number of entries of a key or element, or a `bool` like Qt's `contains`.  Defaults to `count`. |
| `erase_method` | Associative and set: Removes a key or element.  Defaults to `erase`. |
| `insert_method` | Associative: `insert(key, value)`, which has to replace the value of an existing key, like Qt's `insert`.  If not set, `bindgen_map_store` from `bindgen_helper.hpp` assigns or calls `emplace`. |

```yaml
containers:
  - class: std::vector
    type: Sequential
    instantiations:
      - [ "int" ]
      - [ "std::string" ]
  - class: QMap
    type: Associative
    insert_method: insert
    count_method: contains
    erase_method: remove
    instantiations:
      - [ "QString", "int" ]
```

## `parser`

**Mandatory.**  The configuration of the Clang-based C++ parser.

| Key | Description |
|-----|-------------|
| `files` | **Mandatory.**  The headers to parse.  Can be relative to `includes`.  Templated, with environment variables only. |
| `includes` | Include search paths, in addition to the system ones.  Templated: `%` is the project root. |
| `flags` | Flags passed to Clang.  Templated, with environment variables only.  Defaults to `["-x", "c++", "-std=c++11"]`. |
| `defines` | Macros defined for the parse.  Defaults to `__STDC_CONSTANT_MACROS` and `__STDC_LIMIT_MACROS`. |
| `binary` | Path of the parser tool.  Templated, with environment variables only.  Defaults to bindgen's own `clang/parser`. |
| `all_comments` | `true` copies plain `//` and `/* */` comments into the Crystal wrappers too, not just documentation comments.  Defaults to `false`. |

```yaml
parser:
  files: [ my_lib.h ]
  includes: [ "%/ext/include", "{MYLIB_INCLUDE}" ]
  flags: [ "-x", "c++", "-std=c++17" ]
```

Setting `flags` replaces the default, so keep `-x c++` for C++ headers.

Documentation comments (`///`, `/** */`, `//!` and `/*! */`) in front of
classes, methods, fields, enums and functions are copied into the generated
Crystal wrappers.  See [Documentation comments](README.md#documentation-comments).

## `types`

Rules for C++ types, wrapped or not.  All keys are optional.  The rules for
common types like `int`, `bool` and `std::string` are in `builtin_types.yml`,
and can be overridden here.

The keys are C++ type names, and the best match is used: `T*` and `T` can have
different rules.  If no rule matches, the type is decayed and tried again:
`const T*&`, `T*&`, `T**`, `T*`, `T`.

```yaml
types:
  QString:
    binding_type: CrystalString
    crystal_type: String
    from_cpp: "qstring_to_crystal(%)"
    to_cpp: "QString::fromUtf8(%.ptr, %.size)"
  SomeInternalType: { ignore: true }
```

In the conversion templates (`from_cpp`, `to_cpp`, `to_crystal` and
`from_crystal`), `%` is an expression, commonly a call.  If `%` is used more
than once, the expression is evaluated once and bound to `bg_value` first.  In
C++ it is then an lvalue, and the template runs in a lambda; if the expression
is a temporary, what `from_cpp` returns has to outlive it.

### `alias_for`

Makes this type an alias of another type, whose rules are used.  All other
keys are ignored.

```yaml
types:
  qreal: { alias_for: double }
```

A typedef without rules of its own, like `QFileInfoList`, is looked through to
the type it names, `QList<QFileInfo>`, so an alias is only needed when the
typedef's name should map elsewhere.

### `ignore`

If `true`, all methods using this type are ignored.  Useful to get started.

### `kind`

How the type is wrapped and passed in Crystal.  Defaults to `Class`.  Types
listed in [`enums`](#enums) default to `Enum`, unless they have rules here.

* `Class`: The wrapper is a Crystal `class`, a reference to the C++ object.
  One level of indirection is removed: A `T*` in C++ is a `T` in Crystal.
* `Struct`: The wrapper is a Crystal `struct`, passed by value.  No
  indirection is removed: A `T*` in C++ is a `T*` in Crystal too.  Methods are
  called with a pointer to the value in the wrapper.  Built-in types like
  `int` are of this kind.
* `Enum`: A Crystal `enum`, passed by value, used as-is in the wrapper and in
  `lib Binding`.

The fourth kind, `Function`, is used internally for callbacks.  Setting it
doesn't turn a type into a callback.

### `crystal_type`

The name of the type in the Crystal wrapper.

The name is written as is into the generated module, so a type a wrapper
class shadows is qualified: `"::Time::Span"` where `Qt::Time` exists.

### `cpp_type`

The name of the type in the generated C++ code.  Useful with converters.

### `binding_type`

The name of the type in `lib Binding`.  Namespaces become underscores:
`Namespace::Type` is `Namespace_Type`.

### `from_cpp`

C++ code turning the type into the `binding_type`.  `%` is the C++ call.

### `to_cpp`

C++ code turning the `binding_type` into the type.  `%` is the argument.

### `converter`

A Crystal module turning the `binding_type` into the `crystal_type` and back.
Takes precedence over `to_crystal` and `from_crystal`.

```crystal
module TheConverter
  def self.wrap(value : CrystalType) : BindingType
  def self.unwrap(value : BindingType) : CrystalType
end
```

### `to_crystal`

Crystal code turning the `binding_type` into the `crystal_type`, the
counterpart of `from_cpp`.  `%` is the binding call.

```yaml
    to_crystal: "CrystalType.from_cpp(%)"
```

### `from_crystal`

Crystal code turning the `crystal_type` into the `binding_type`, the
counterpart of `to_cpp`.  `%` is the wrapper's argument.

```yaml
    from_crystal: "%.to_cpp"
```

### `pass_by`

Overrides how the type is passed: `Original` (default, as in C++),
`Reference`, `Pointer` or `Value`.  Usually not needed.

A type passed by `Value` and converted both ways by `to_cpp` and `from_cpp`,
like `QString`, is exchanged as a temporary.  A method taking it by non-const
reference or by pointer gets an *out argument*: the wrapper returns the value
written back with its result (SPEC.md §2.2.5).  Constructors and operators
with such an argument are dropped, as are methods taking a `const` pointer or
a pointer to a pointer to it.  A method keeping the pointer, like
`QTextStream::setString`, has to be listed in `ignore_methods`.

A copied structure passed by `Value` with a wrapper, like `QPoint`, is taken
by non-const reference or pointer as a pointer to its storage, which the
method writes into: the wrapper object, or a `kind: Struct` wrapper by
`pointerof` (SPEC.md §2.2.1).

### `wrapper_pass_by`

Like `pass_by`, only in the Crystal wrapper.  Defaults to `pass_by`.

### `sub_class`

If `true`, the type gets a C++ sub-class so its virtual methods can be
overridden in Crystal.  Types without virtual methods never get one.  Defaults
to `true`.

### `copy_structure`

If `true`, the fields of the C++ structure are copied into a `struct` in
`lib Binding`, for simple C-style structures.  If the type also has a wrapper
class, it holds the structure instead of a pointer to it.  Defaults to
`false`.

Structures which aren't trivially copyable, or with members a `lib struct`
can't hold, like a `std::string`, are refused.  See
[CopyStructs](README.md#copystructs).

### `bit_fields`

How the getters and setters of the bit-fields of a copied structure access
them:

| Value | Description |
|-------|-------------|
| `Accessors` | Calls C++ getter and setter functions.  Works on any platform.  The default. |
| `Inline` | Shifts and masks the bits in Crystal.  Faster, but only correct on platforms with the bit-field layout of the one the code was generated on. |

```yaml
types:
  Flags: { copy_structure: true, bit_fields: Inline }
```

See [Bit-fields](README.md#bit-fields).

### `instance_variables`

Property methods for the static and instance data members.  Defaults to
`true`.

* `true`: All members get property methods.
* `false`: No member gets property methods.
* A mapping: Each key is a regular expression matching member names, and its
  value configures the matched members:
  * `ignore:` if `true`, no property methods.  Defaults to `false`.
  * `rename:` the name of the methods.  `\\1` is the first capture group, and
    so on.  Underscoring is applied afterwards.
  * `nilable:` if `true`, the methods of a pointer member take and return
    `nil` for a null pointer.  Defaults to `false`.

```yaml
types:
  MyClass:
    instance_variables:
      "^m_(.*)$": { rename: "\\1" }
      "^d_ptr$": { ignore: true }
```

`copy_structure: true` suppresses the property methods, unless the type has a
wrapper class.

### `builtin`

If `true`, the type is treated as built-in in C++ and Crystal.  Defaults to
`false`.

### `generate_wrapper`

If `false`, the Crystal wrapper class isn't generated.  Defaults to `true`.

### `generate_binding`

If `false`, the `fun` bindings of the type's methods aren't generated.
Defaults to `true`.

### `generate_superclass`

If `false`, the `Superclass` wrapper struct and `#superclass` method, used to
call the C++ implementation of an overridden virtual method, aren't generated.
Defaults to `true`.

### `ignore_methods`

Methods of this type to ignore.  An entry is one of:

* A C++ name, dropping every overload of it: `someMethod`
* A C++ signature, dropping that overload only: `operator-(const QDateTime &,
  const QDateTime &)`, or `validate(QString &, int &) const` for a const
  method.  The argument types are written like the parser prints them, with a
  space before `*` and `&` and after commas; other spacing is normalized.
* A regular expression between slashes, matched against that signature:
  `/^operator\*\(.*QVector3D/`

```yaml
    ignore_methods:
      - someMethod
      - "operator-(const QDateTime &, const QDateTime &)"
      - "/^operator\\*\\(.*QVector3D/"
```

### `declare_methods`

C++ declarations of methods the parser doesn't report, as written in a
header, which the generated C++ calls like any other method.  This binds the
instantiations of template members, like `QAction::menu` and `setMenu` in Qt
6, which are templates over the menu type, or `QMutex::tryLockFor`.  Every
argument is named, like in a declaration; a default is exposed to Crystal if
it's a literal number, boolean or `nullptr`.  `static` and `const` are
understood; constructors and operators aren't.

```yaml
    declare_methods:
      - "QMenu *menu() const"
      - "void setMenu(QMenu *menu)"
      - "bool tryLockFor(std::chrono::milliseconds duration)"
```

### `shadowed_by`

Types whose overloads shadow those taking this type: an overload of a method
taking this type is dropped where another overload takes one of the listed
types in its place, with the other arguments equal.  For a view type
converted like the type it views, which would take the same Crystal
arguments: `QString::indexOf(QStringView)` next to `indexOf(const QString
&)`.  An overload without such a twin stays, converted by the view's rules.

```yaml
  QStringView:
    shadowed_by: [QString]
  QLatin1StringView:
    shadowed_by: [QString, QStringView]
```

### `rename`

Crystal names of methods, by the entries of `ignore_methods`: a C++ name
renames every overload, a signature one of them, a regular expression between
slashes those matching.  The first matching entry names the method.  A
renamed virtual method is overridden under its Crystal name.

```yaml
    rename:
      raise: raise_ # Would shadow Crystal's raise in a subclass
      "toUnicode(QString *, const char *, int)": decode
```

### `nilable`

Whether the pointer result and arguments of methods accept `nil`, by the
entries of `ignore_methods`.  `true` or `false` makes the result `T?` or `T`,
regardless of `nilable_results`.  A list of argument indices makes those
arguments accept `nil`, like one defaulting to `nullptr` does; the `nil`
reaches C++ as a null pointer.  Only pointers to wrapped classes are
affected.

```yaml
    nilable:
      menuBar: false # Qt creates one
      setModel: [0]  # A null model is allowed
```

### `superclass_ignore_methods`

Regular expressions of method names to leave out of the `Superclass` wrapper.

```yaml
    superclass_ignore_methods: [ ^full_method_name$, ^prefix_ ]
```

### `keep_alive`

Methods which keep a pointer to some of their arguments, like a setter storing
an object in a data member.  Their wrapper methods pass these arguments to
`BindgenHelper.keep_alive`, so the GC doesn't collect objects still used by
C++.  `BindgenHelper.release` lets the GC collect one again, and so does C++
deleting it.  Only instances of wrapped classes passed by pointer or reference
are kept.  Defaults to keeping nothing.

* A list: Each element is a regular expression; all arguments of the matched
  methods are kept.
* A mapping: Each key is a regular expression, and its value a list of the
  indices of the arguments to keep, `true` for all of them, or `false` for
  none.

The expressions are matched against the C++ method name, the name of the data
member for its setter, and an empty string for constructors.  Copy
constructors never keep their argument.  An expression matching no method of
the class, like a misspelt or ignored one, is warned about.  Methods bound from
a superclass follow the rules of the superclass, and so does a method a
subclass re-declares, like an override: the rules of the base classes apply to
it, together with its own.

```yaml
types:
  QStatusBar:
    keep_alive: [ ^addWidget$, ^addPermanentWidget$ ]
  QLayout:
    keep_alive:
      ^addWidget$: [0]
      ^$: false
```

See [Objects kept alive for C++](README.md#objects-kept-alive-for-c).

### `release`

Methods handing an object back, which C++ stops using without deleting it,
like a widget taken out of a layout.  Their wrapper methods pass the selected
object arguments, and the result when all arguments are selected (a list
entry, or `true`), to `BindgenHelper.release`, so the GC may collect an
object `keep_alive` kept.  Same format and matching as
[`keep_alive`](#keep_alive); constructors are ignored.  Defaults to releasing
nothing.

```yaml
types:
  QLayout:
    keep_alive: [^addWidget$, ^addItem$]
    release:
      ^takeAt$: true       # The result
      ^removeWidget$: true # The argument
      ^replaceWidget$: [0] # The first argument only
```

### `parent_arguments`

Names of the constructor arguments giving the object a parent, which owns and
deletes it, in a class the [`Qt`](README.md#qt) processor doesn't know to be
owned by its parent: the classes deriving from `QObject`, `QGraphicsItem` and
`QGraphicsLayoutItem` have `parent` built in.  The processor keeps the object
alive while it has a parent, like a child of a `QObject`, and lets it go as the
parent deletes it.  The rule applies to the subclasses too.  A name matching no
object argument of a constructor is warned about.  Defaults to none.

```yaml
types:
  QTreeWidgetItem:
    parent_arguments: [parent, treeview] # QTreeWidgetItem(QTreeWidgetItem *parent, ...), QTreeWidgetItem(QTreeWidget *treeview, ...)
  QListWidgetItem:
    parent_arguments: [listview]
```

See [Objects kept alive for C++](README.md#objects-kept-alive-for-c).

### `depends_on`

Constructors and member methods whose object refers to some of their
arguments from memory the GC doesn't scan, like through a d-pointer, and uses
them when destroyed, like an iterator unregistering from its container, or a
stream writing to its device.  The C++ glue stores the arguments in the object,
so the GC keeps them alive as long as it, and destroys them only after it.
Same format as [`keep_alive`](#keep_alive), matched against an empty string for
constructors.  A copy made by the copy constructor depends on the object it
copies.  A method replaces the dependencies the object had by its arguments,
before it runs; a null argument leaves none.  A method does nothing on an
object C++ created.  The constructors and methods of copied, aggregate, union
and `final` classes are ignored with a warning, as these don't allocate the
object the GC scans, and so are static methods and an expression matching no
method of the class.  Defaults to depending on nothing.

```yaml
types:
  QTreeWidgetItemIterator:
    depends_on: [ ^$ ]
  QPainter:
    depends_on: [ ^$, ^begin$ ] # The paint device
```

See [Objects destroyed before others](README.md#objects-destroyed-before-others).
