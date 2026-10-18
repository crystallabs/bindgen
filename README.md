# Bindgen

Standalone C, C++, and/or Qt binding and wrapper generator.

![Logo](https://raw.githubusercontent.com/Papierkorb/bindgen/master/images/logo.png) [![CI](https://github.com/Papierkorb/bindgen/actions/workflows/ci.yml/badge.svg)](https://github.com/Papierkorb/bindgen/actions/workflows/ci.yml)

## Installation

Add the dependency to `shard.yml`:

```yaml
dependencies:
  bindgen:
    github: Papierkorb/bindgen
    version: ~> 0.10.0
```

# Table of Contents

The configuration keys are described in [CONFIGURATION.md](CONFIGURATION.md).

<!--ts-->
   * [How To](#how-to)
   * [Projects using bindgen](#projects-using-bindgen)
   * [Mapping behaviour](#mapping-behaviour)
   * [Features](#features)
   * [Architecture of bindgen](#architecture-of-bindgen)
      * [The Graph](#the-graph)
      * [Parser step](#parser-step)
      * [Graph::Builder step](#graphbuilder-step)
      * [Processor step](#processor-step)
      * [Generator step](#generator-step)
   * [Processors](#processors)
      * [AutoContainerInstantiation](#autocontainerinstantiation)
      * [BlockOverloads](#blockoverloads)
      * [CopyStructs](#copystructs)
         * [Bit-fields](#bit-fields)
      * [CppWrapper](#cppwrapper)
      * [CrystalBinding](#crystalbinding)
      * [CrystalWrapper](#crystalwrapper)
         * [Objects kept alive for C++](#objects-kept-alive-for-c)
      * [DefaultConstructor](#defaultconstructor)
      * [DumpGraph](#dumpgraph)
      * [Enums](#enums)
      * [ExternC](#externc)
      * [FilterMethods](#filtermethods)
      * [Functions](#functions)
      * [FunctionClass](#functionclass)
      * [Inheritance](#inheritance)
      * [InstanceProperties](#instanceproperties)
      * [InstantiateContainers](#instantiatecontainers)
      * [Macros](#macros)
      * [Operators](#operators)
      * [Qt](#qt)
      * [SanityCheck](#sanitycheck)
      * [VirtualOverride](#virtualoverride)
   * [Documentation comments](#documentation-comments)
   * [Advanced configuration features](#advanced-configuration-features)
      * [Conditions](#conditions)
         * [Variables](#variables)
         * [Examples](#examples)
      * [Dependencies](#dependencies)
         * [Errors](#errors)
   * [Platform support](#platform-support)
   * [Contributing](#contributing)
      * [Contributors](#contributors)
   * [License](#license)

<!--te-->

# How To

When you have a Crystal project and want to bind to C, C++, or Qt libraries
with the help of `bindgen`, do as follows:

1. Add bindgen to your project's `shard.yml` as instructed above under "Installation" and then run `shards`
2. Copy `lib/bindgen/assets/bindgen_helper.hpp` into your `ext/` subdirectory, creating it if missing. Copy it again whenever you upgrade bindgen, as the generated code relies on the matching version
3. Copy `lib/bindgen/TEMPLATE.yml` into `your_template.yml` (adjust the name to your liking) and customize it for the library you want to bind to. Every key is described in [CONFIGURATION.md](CONFIGURATION.md)
4. Run `lib/bindgen/tool.sh your_template.yml`. This will generate the bindings, and by default place the outputs in the `ext/` subdirectory
5. Develop your Crystal application as usual

**Note**: If you ship the output produced by bindgen along with your application,
then `bindgen` will not be not required to compile it. In that case, you can move
its entry in `shard.yml` from `dependencies` to `development_dependencies`.

The `.yml` file that you copy from `TEMPLATE.yml` will contain the complete
configuration template along with accompanying documentation embedded in
the comments.
If you prefer working with shorter files, you can simply remove all the
comments.  [CONFIGURATION.md](CONFIGURATION.md) describes the same keys as a
reference.

# Projects using bindgen

You can use the following projects' .yml files as a source of ideas or syntax for
your own bindings:

* [Qt5 Bindings](https://github.com/Papierkorb/qt5.cr)

*Have you created and published a usable binding with bindgen? Want to see it here? Send a PR!*

# Mapping behaviour

The following rules are automatically applied to all bindings:

* Method names get underscored: `addWidget() -> #add_widget`
  * Setter methods are rewritten: `setWindowTitle() -> #window_title=`
  * Getter methods are rewritten: `getWindowTitle() -> #window_title`
  * Bool getters are rewritten: `getAwesome() -> #awesome?`
  * `is` getters are rewritten: `isEmpty() -> #empty?`
  * `has` getters are rewritten: `hasSpace() -> #has_space?`
* On signal methods (For Qt signals):
  * Keep their name for the `emit` version: `pressed() -> #pressed`
  * Get an `on_` prefix for the connect version: `#on_pressed do .. end`
* Enum fields get title-cased if not already: `color0 -> Color0`

# Features

| Feature                                          | Support |
|--------------------------------------------------|---------|
| Automatic Crystal binding generation             | **YES** |
| Automatic Crystal wrapper generation             | **YES** |
| Mapping C++ classes                              |         |
|  +- Member methods                               | **YES** |
|  +- Static methods                               | **YES** |
|  +- Getters and setters for instance variables   | **YES** |
|  +- Getters and setters for static variables     | **YES** |
|  +- Constructors                                 | **YES** |
|  +- Copy constructors, assignment operators      | **YES** |
|  +- Overloaded operators                         | Partial |
|  +- Conversion functions                         | **YES** |
| Mapping C/C++ global functions                   |         |
|  +- Mapping global functions                     | **YES** |
|  +- Wrapping as Crystal class                    | **YES** |
| Overloaded methods (Also default arguments)      | **YES** |
| C arrays in methods                              |         |
|  +- References to arrays, as `Slice`             | **YES** |
|  +- Pointers to arrays, as `StaticArray` pointer | **YES** |
|  +- Arrays of wrapped types, as `ArrayView`      | **YES** |
| Copying default argument values                  |         |
|  +- Integer, float, boolean types                | **YES** |
|  +- String                                       | **YES** |
| Enumerations                                     | **YES** |
| Copying structures                               | **YES** |
|  +- C array members of built-in types            | **YES** |
|  +- C array members of wrapped types             |   TBD   |
|  +- Bit-fields                                   | **YES** |
| Custom type conversions between C/++ and Crystal | **YES** |
| Automatic type wrapping and conversion           | **YES** |
| Integration with Crystals GC                     | **YES** |
|  +- Keeping objects passed to C++ alive          | **YES** |
| C++ Template instantiation for containers types  |         |
|  +- Sequential containers                        | **YES** |
|  +- Associative containers                       | **YES** |
| C++ class template instantiations                |         |
|  +- Type and integral non-type arguments         | **YES** |
|  +- Default template arguments                   | **YES** |
|  +- Generic Crystal type (`Box(T)`)              |   TBD   |
|  +- Automatic instantiation                      |   TBD   |
| Virtual methods                                  | **YES** |
| Override virtual methods from Crystal            | **YES** |
| Abstract classes                                 | **YES** |
| Multiple inheritance wrapping                    | **YES** |
| Downcasting polymorphic classes (`#to?`)         | **YES** |
| Qt integration                                   |         |
|  +- QObject signals                              | **YES** |
|  +- QFlags types                                 | **YES** |
|  +- QMetaObject generation (mimic `moc`)         |   TBD   |
| `#define` macro support                          |         |
|  +- Mapping as enumeration                       | **YES** |
|  +- Mapping as constant (Including strings)      | **YES** |
| Copying in-source docs                           | **YES** |
| Platform specific type binding rules             | **YES** |
| Portable path finding for headers, libs, etc.    | **YES** |

# Architecture of bindgen

Bindgen employs a pipeline-inspired code architecture, which is strikingly
similar to what most compilers use.

The code flow is basically `Parser::Runner` to `Graph::Builder` to
`Processor::Runner` to `Generator::Runner`.

![Architecture flow diagram](https://raw.githubusercontent.com/Papierkorb/bindgen/master/images/architecture.png)

## The Graph

An important data structure used throughout the program is *the graph*.
Code-wise, it's represented by `Graph::Node` and its sub-classes.  The nodes
can contain child nodes, making it a hierarchical structure.

This allows to represent (almost) arbitrary structures as defined by the user
configuration.

Say we're wrapping `GreetLib`.  As any library, it comes with a bunch of
classes (`Greeter` and `Listener`), enums  (`Greetings`, `Type`) and other stuff
like constants (`PORT`).  The configuration file could look like this:

```yaml
module: GreetLib
classes: # We copy the structure of classes
  Greeter: Greeter
  Listener: Listener
enums: # But map the enums differently
  Type: Greeter::Type
  Greeter::Greetings: Greetings
```

Which will generate a graph looking like this:

![Graph example](https://raw.githubusercontent.com/Papierkorb/bindgen/master/images/graph.png)

**Note**: The concept is really similar to ASTs used by compilers.

## Parser step

This is the beginning of the actual execution pipeline. It calls out to the clang-based parser
tool () to read the C/C++ source code and write a JSON-formatted "database" onto
standard output.  This is directly read by `bindgen` and subsequently parsed
as `Parser::Document`.

## Graph::Builder step

The second step takes the `Parser::Document` and transforms it into a
`Graph::Namespace`.  This step is where the user configuration mapping is used.

## Processor step

The third step runs all configured processors in order.  These work with the
`Graph` and mostly add methods and `Call`s so they can be bound later.  But
they're allowed to do whatever they want really, which makes it a good place
to add more complex rewriting rules if desired.

Processors are responsible for many core features of bindgen.  The `TEMPLATE.yml`
has an already set-up example pipeline.

## Generator step

The final step now takes the finalized graph and writes the result into an
output of one or more files.  Generators do *not* change the graph in any way,
and also don't build anything on their own.  They only write to output.

# Processors

The processor pipeline can be configured through the `processors:` array.  Its
elements are run in the order they're defined, starting at the first element.

**Note**: Don't worry: The `TEMPLATE.yml` file already comes with the
recommended pipeline pre-configured.

There are three kinds of processors:
1. *Refining* ones modify the graph in some way, without a dependency to a later
   generator.
2. *Generation* processors add data to the graph so that the generators
   run later have all data they need to work.
3. *Information* processors don't modify the graph, but do checks or print data
   onto the screen for debugging purposes.

The order in the configured pipeline is to have *Refining* processors first,
*Generation* processors second. *Information* processors can be run at any time.

The following processors are available, in alphabetical order:

## `AutoContainerInstantiation`

* **Kind**: Refining
* **Run after**: No specific dependency
* **Run before**: `InstantiateContainers`

When encountering a known container class on an instantiation that is not
registered yet, registers it.

Container classes still need to be declared in the configuration, but don't
require an explicit `instantiations` attribute anymore:

```yaml
containers: # At the top-level of the config
  - class: QList # Set the class name
    type: Sequential # And its type
    # instantiations: # Can be added, but doesn't need to be.
```

## `BlockOverloads`

* **Kind**: Refining, but ran after generation processors!
* **Run after**: `CrystalWrapper`, `Qt`
* **Run before**: No specific dependency

Adds type parameters to ambiguous Crystal methods that take a single block
argument, so that these methods can be overloaded by passing the parameter types
of that argument to the method.  `Qt` needs it for several signal connection
methods.

```crystal
cb = Qt::ComboBox.new
cb.on_activated(Int32) do |index| # Type argument added by this processor
  puts "Int32 overload selected: #{index}"
end
cb.on_activated(String) do |text| # Type argument added by this processor
  puts "String overload selected: #{text}"
end
```

## `CopyStructs`

* **Kind**: Refining
* **Run after**: No specific dependency
* **Run before**: No specific dependency

Copies structures of those types, that have `copy_structure: true` set in the
configuration, into `lib Binding`.  Such a type is passed by value.  It has to
be layout-compatible to a C structure: Its members may only be built-in types,
enumerations, other copied structures and pointers.  A pointer to a type which
is converted, like `std::string *`, becomes a `Void*`.  bindgen refuses to copy
a structure with a member it can't represent, like a `std::string`, a container
or a class which isn't copied itself, and one whose C++ type isn't trivially
copyable and standard-layout.

A structure packed by `__attribute__((packed))` or `#pragma pack(1)` becomes a
`@[Packed]` `lib struct`.  Other packing is refused, as Crystal can't express
it: `#pragma pack(N)` with N above 1, a packed union, and a packed structure
with a member which keeps its alignment, like one with an `aligned` attribute,
or one of a non-POD type on targets other than Darwin.  Packing that doesn't
move any member, like `#pragma pack(4)` around `char` and `short` members, is
ignored.

A wrapper class of a `copy_structure` type will host the structure directly
(instead of a pointer) to it:

* `#to_unsafe` returns a pointer to the hosted structure.
* A structure received from C++ by value, reference or pointer is *copied* into
  a new wrapper instance.  Changing it doesn't change the original.
* Property methods are generated for the members, see `InstanceProperties`.

Set `generate_wrapper: false` and `generate_binding: false` to only get the
`lib struct`.

### Bit-fields

Crystal has no bit-fields, so each run of consecutive bit-fields is stored in
unsigned integer members named `_bits0`, `_bits1` and so on, one for each unit
of storage the bit-fields occupy.  The `lib struct` gets a getter and a setter
for each named bit-field:

```c++
struct Flags {
  unsigned narrow : 3;
  int wide : 12;
};
```

```crystal
flags = Binding::Flags.new
flags.wide = -7
flags.wide # => -7
```

The type option `bit_fields` sets how these methods access the bits:

* `Accessors` (the default) calls C++ getter and setter functions, generated
  for each bit-field.  This works on any platform the C++ wrapper is compiled
  for, at the cost of a function call for each access.
* `Inline` shifts and masks the bits in Crystal, without calling C++.  The
  generated code uses the bit layout of the platform it was generated on, and
  is only correct on platforms laying out bit-fields the same way.  The common
  Unix platforms on x86_64 and arm64 share it, Windows doesn't.

The `lib struct` follows the layout of the Itanium C++ ABI, used by GCC and
Clang outside of Windows: A run of bit-fields is stored in units of its largest
type, which also hold the smaller ones.  Members named `_pad0`, `_pad1` and so
on pad the structure where a zero-width bit-field like `unsigned : 0` moves the
next member.  In a `lib union`, each bit-field has its own storage member.

A wrapper class hosting the structure accesses all members through C++,
bit-fields included, regardless of `bit_fields`.

These structures are refused, with an error saying why:

* A bit-field sharing its storage unit with the member before the run, as in
  `char c; unsigned bits : 3;`.  The bit-fields would have to start inside the
  unit, which a `lib struct` can't express.
* A member sharing the last storage unit of the run, as in
  `unsigned bits : 3; char c;`, for the same reason.
* A bit-field of another type than an integer type or `bool`, like an
  enumeration or `wchar_t`.  Integer types are `char`, `short`, `int`, `long`
  and `long long`, signed or unsigned, the fixed-size types like `uint32_t`,
  and `size_t` and `ssize_t`.
* A bit-field in a packed structure, as these are packed together with the
  members after them bit by bit.
* With `bit_fields: Accessors`, a structure of an anonymous type, like the type
  of `member` in `struct { unsigned bits : 3; } member;`.  The C++ accessors
  can't name the type.  Use `bit_fields: Inline` instead.
* A bit-field crossing a storage unit.  GCC and Clang never lay out one this
  way.

A class that isn't copied, but wrapped, has none of these restrictions: Its
property methods access the bit-fields through C++, see
[InstanceProperties](#instanceproperties).

## `CppWrapper`

* **Kind**: Generation
* **Run after**: *Refining* processors
* **Run before**: `CrystalBinding`

Generates the C++ wrapper method `Call`s.

## `CrystalBinding`

* **Kind**: Generation
* **Run after**: `CppWrapper`, `VirtualOverride` and `CrystalWrapper`
* **Run before**: No specific dependency

Generates the `lib Binding` `fun`s.

## `CrystalWrapper`

* **Kind**: Generation
* **Run after**: *Refining* processors
* **Run before**:  `CrystalBinding` and `VirtualOverride`

Generates the Crystal methods in the wrapper classes.

### Objects kept alive for C++

Objects constructed from Crystal are allocated by the GC, which only sees
pointers in memory it scans.  If C++ code keeps a pointer to one elsewhere, like
in a member of an object allocated with plain `new`, the GC collects it once the
Crystal wrapper is gone, while C++ still uses it.  With Qt, which keeps widgets
added to layouts this way, this crashes in the GC's finalizers
([Papierkorb/bindgen#75](https://github.com/Papierkorb/bindgen/issues/75)).

Configure the methods keeping a pointer to their arguments in `keep_alive:` of
the class.  Their wrapper methods pass the arguments, if they are wrapped
objects passed by pointer or reference, to `BindgenHelper.keep_alive`.  It
stores the wrapper, which refers to the C++ object, until it's passed to
`BindgenHelper.release`.  `BindgenHelper` is part of the generated module.

Objects are kept by the address of their C++ object, as getters return a new
wrapper each time: any wrapper of it, or its pointer, releases it.  Nothing is
released automatically, so an object C++ deletes stays in the table until
released.  If the library notifies of destruction, like Qt's
`QObject::destroyed`, release it from there: `.release` may run in a GC
finalizer.

```yaml
types:
  QStatusBar:
    keep_alive: [^addWidget$, ^addPermanentWidget$, ^insert]
  Outer:
    keep_alive:
      ^inside$: true # The setter of the `inside` member
      ^$: [0]        # Only the first argument of constructors
```

```crystal
label = Qt::Label.new("Ready")
status_bar.add_widget(label) # Keeps the label alive
status_bar.remove_widget(label)
Qt::BindgenHelper.release(label) # Lets the GC collect it again
```

See `TEMPLATE.yml` for details.

## `DefaultConstructor`

* **Kind**: Refining
* **Run after**: No specific dependency
* **Run before**: No specific dependency

Clang doesn't expose default constructors methods for implicit default
constructors.  This processor finds these cases and adds an explicit
constructor.  Also, generates constructors for aggregate types.

## `DumpGraph`

* **Kind**: Information
* **Run after**: Any time
* **Run before**: Any time

Debugging processor dumping the current graph onto `STDERR`.

## `Enums`

* **Kind**: Refining
* **Run after**: `FunctionClass`
* **Run before**: No specific dependency

Adds the copied enums to the graph.  Should be run after other processors adding
classes, so that enums can be added into classes.

## `ExternC`

* **Kind**: Refining
* **Run after**: `Functions` and `FunctionClass`
* **Run before**: No specific dependency

Checks if a method require a C/C++ wrapper.  If not, marks the method to
bind directly to the target method instead of writing a "trampoline"
wrapper in C++.

**Note**: This processor is *required* for variadic functions to work.  A
variadic function looks like this: `void func(int c, ...);`

A method can be bound directly if all of these are true:

1. It uses the C ABI (`extern "C"`)
2. No argument uses a `to_cpp` converter
3. The return type doesn't use a `from_cpp` converter

**Note**: If all methods can be bound to directly, you can remove the `cpp`
generator completely from your configuration.

## `FilterMethods`

* **Kind**: Refining
* **Run after**: No specific dependency
* **Run before**: No specific dependency

Removes all methods using an argument, or returning something, which is
configured as `ignore: true`.  Also removes methods that show up in the
`ignore_methods:` list.

This processor can be run at any time in theory, but should be run as first part
of the pipeline.

## `Functions`

* **Kind**: Refining
* **Run after**: `FunctionClass` and `ExternC`
* **Run before**: No specific dependency

Maps C functions, configured through the `functions:` map in the configuration.

## `FunctionClass`

* **Kind**: Refining
* **Run after**: `ExternC`
* **Run before**: `Inheritance` and `Functions`

Generates wrapper classes from OOP-like C APIs, using guidance from the user
through configuration in the `functions:` map.

## `Inheritance`

* **Kind**: Refining
* **Run after**: `FunctionClass`
* **Run before**: `FilterMethods` and `VirtualOverride`

Implements Crystal wrapper inheritance and adds `#as_X` conversion methods.
The Crystal superclass is the first wrapped base at offset 0 in the C++ class,
the other bases are reached through `#as_X`, and their methods are wrapped in
the derived class too.  Also handles abstract classes in that it adds an `Impl`
class, so code can return instances to the (otherwise) abstract class.

Adds `#to?(T.class)` casting methods, which also cast down between polymorphic
classes through a `dynamic_cast`, returning `nil` if the object isn't a `T`:
`Bar.create.to?(Foo) # => Foo?`.  See `SPEC.md` §2.3.6.  Downcasts use
`dynamic_cast`: if the C++ code is built without RTTI (`-fno-rtti`, like Qt),
one aborts the program instead.

## `InstanceProperties`

* **Kind**: Refining
* **Run after**: No specific dependency
* **Run before**: No specific dependency

Generates getter and setter methods for static and instance members.

The members of an unnamed member of anonymous type are accessed as members of
the enclosing class.  A named member of anonymous type gets a wrapper class
named after the type's position in the enclosing class, like
`Wrapped::Unnamed0` for the first anonymous `struct` or `union` in `Wrapped`,
with property methods of its own.  The getter returns a wrapper referring to
the member inside the object instead of a copy.  This pointer into the object
keeps an object allocated by bindgen alive.

```c++
struct Wrapped {
  struct { int y; } z;
};
```

```crystal
w = Wrapped.new
w.z.y = 5     # Changes `w`
w.z = other.z # Copies the member
```

As C++ code can't name the anonymous type, it is declared as
`typedef decltype(Wrapped::z) Wrapped_Unnamed0;`.  Static, `const` and pointer
members of anonymous type are skipped, and so are members of anonymous type
nested inside an unnamed member.

## `InstantiateContainers`

* **Kind**: Refining
* **Run after**: `AutoContainerInstantiation` if used
* **Run before**: No specific dependency

Adds the container instantiation classes and wrappers.

Each container class also gets a generic module, e.g. `QList(T)`.  Use it as
type restriction, or get the wrapper class of an instantiation through its `of`
macro: `QList.of(Int32).new`.  See `SPEC.md` for details.

Wrappers of sequential containers, like `std::vector`, are `Indexable`.
Wrappers of associative containers, like `std::map`, `std::unordered_map`,
`QMap` and `QHash`, offer a `Hash`-like interface: `#[]`, `#[]?`, `#[]=`,
`#has_key?`, `#delete`, `#size`, `#keys`, `#values` and `#to_h`, and they are
`Enumerable` over tuples of the key and the value.  `#each` iterates over a
copy of the entries, so changing the container meanwhile is safe.  Any
`Enumerable` of such tuples, like a `Hash`, is accepted where C++ expects the
container.

```crystal
lengths = Std::Map.of(String, Int32).from({"one" => 3})
lengths["three"] = 5
lengths.each { |word, length| puts "#{word}: #{length}" }
```

Associative containers call the C++ methods `count(key)`, `erase(key)` and
`size()`, and the helpers `bindgen_map_fetch`, `bindgen_map_store` and
`BindgenMapEntries` from `bindgen_helper.hpp`.  For Qt, configure the method
names:

```yaml
containers:
  - class: std::map
    type: Associative
  - class: QMap
    type: Associative
    count_method: contains
    erase_method: remove
    insert_method: insert # Instead of `bindgen_map_store`, which needs `emplace`
```

## `Macros`

* **Kind**: Refining
* **Run after**: No specific dependency
* **Run before**: No specific dependency

Maps `#define` macros into the graph.  The mapping is configured by the user in
the `macros:` list.  Only value-macros ("object-like macros") are supported,
function-like macros are silently skipped.

```c++
// Okay:
#define SOME_INT 1
#define SOME_STRING "Hello"
#define SOME_BOOL true

// Not mapped:
#define SOME_FUNCTION(x) (x + 1)
```

## `Operators`

* **Kind**: Refining
* **Run after**: No specific dependency
* **Run before**: No specific dependency

Performs special handling for operator methods.

Operators are wrapped as methods named after them; those Crystal can't
overload get a name, like `operator=` becoming `#assign!`.  Conversion
operators become `#to_` and the type, like `#to_bool` for `operator bool()`.  A
copy constructor becomes an overload of `.new` taking the object to copy.

## `Qt`

* **Kind**: Refining
* **Run after**: No specific dependency
* **Run before**: `BlockOverloads`

Adds Qt specific behaviour:

1. Removes the `qt_check_for_QGADGET_macro` fake method.
2. Provides `#on_SIGNAL` signal connection method.
3. Removes `#meta_object`, `#qt_metacast`, and `#qt_metacall` from superclass
   wrappers, as these shouldn't be overridden by the user.

```crystal
btn = Qt::PushButton.new
btn.on_clicked do |checked| # Generated by this processor
  puts "Checked: #{checked}"
end
```

## `SanityCheck`

* **Kind**: Information
* **Run after**: Any time, as very last pipeline element is ideal.
* **Run before**: Any time

Does sanity checks on the graph, focusing on Crystal bindings and wrappers.

Checks are as follows:
* Name of enums, libs, structures, classes, modules and aliases are valid
* Name of constants are valid
* Name of methods are valid
* Enumerations have at least one constant
* Flag-enumerations don't have `All` nor `None` constants
* Crystal method overloads are unambiguous
* Method arguments and result types are reachable
* Variadic methods are directly bound
* Alias targets are reachable
* Class base-classes are reachable
* Structure fields are of a supported and reachable type

## `VirtualOverride`

* **Kind**: Refining, but ran after generation processors!
* **Run after**: `CrystalWrapper`!
* **Run before**: `CrystalBinding` and `CppWrapper`

Adds C++ and Crystal wrapper code to allow overriding C++ virtual methods from
within Crystal.  Requires the `Inheritance` processor.

**Important Note**: Make sure to run this processor after `CrystalWrapper` but
before `CrystalBinding`.

It needs to modify the `#initialize` methods, and generate `lib` structures,
bindings, and C++ code too.

This is the recommended processor order:

```yaml
processors:
  # ...
  - crystal_wrapper
  - block_overloads
  - virtual_override
  - cpp_wrapper
  - crystal_binding
```

After this, usage is the same as with any method:

```crystal
class MyAdder < VirtualCalculator
  # In C++: virtual int calculate(int a, int b) = 0;
  # In Crystal:
  def calculate(a, b) : Int32
    a + b
  end
end
```

**Do NOT call `super` in the body of a Crystal method that overrides a concrete
C++ virtual method!**  Due to Bindgen's limitations, doing so will result in a
stack overflow immediately.  Instead, Bindgen provides a _private_ `#superclass`
method in every concrete abstract class; it wraps the calling instance so that
the original C++ methods can be called, bypassing Crystal's overrides.

```crystal
class MyLogger < Calculator
  # In C++:
  # virtual void clear_memory();
  # virtual void add_memory(int m);

  # In Crystal:
  def clear_memory : Nil
    puts "M = 0"
    superclass.clear_memory
  end

  def add_memory(m) : Nil
    puts "M += #{m}"
    # unlike `super`, all arguments are mandatory
    superclass.add_memory(m)
  end
end
```

# Documentation comments

Documentation comments in the C++ headers are copied into the generated
Crystal wrapper, in front of the wrapped classes, methods, enums and module
functions.  The comments of a field are copied to its getter and setter.  For a
class template instantiation, the comments of the template are used.

```c++
/// A point on the screen.
struct Point {
  /** Moves the point by *dx* and *dy*.
   *  @param dx Horizontal distance. */
  void move(int dx, int dy);

  int x; ///< Horizontal position.
};
```

```crystal
# A point on the screen.
class Point
  # Moves the point by *dx* and *dy*.
  # @param dx Horizontal distance.
  def move(dx : Int32, dy : Int32) : Void

  # Horizontal position.
  def x() : Int32
```

By default only documentation comments are copied: `///`, `//!`, `/** */` and
`/*! */`, plus the trailing `///<` form.  Set `all_comments: true` under
`parser:` to copy plain `//` and `/* */` comments too.  Clang ignores comments in
system headers, which includes headers found through `-isystem`.

The comment text is copied as written, without the comment markers.  Doxygen
commands like `@param` and `\brief` aren't converted, and show up as is in
the Crystal API documentation.  Comments of enumerators and of `#define` macros
aren't copied.

# Advanced configuration features

Bindgen's YAML configuration files support conditional definitions
as well as loading external dependency files.

Apart from that extra logic, the configuration file is still valid YAML.

**Note**: Conditionals and dependencies are *only* supported in YAML
*mappings* (data structures equivalent to `Hash`es in Crystal).
Any such syntax encountered in something other than a *mapping* will not
trigger special behaviour.

## Conditions

YAML documents can define conditional parts in *mappings* by having a
conditional key with *mapping* value.  If the condition matches, the
*mapping* value will be transparently embedded.  If it does not match, the
value will be transparently skipped.

Condition keys look like `if_X` or `elsif_X` or `else`.  `X` is the
condition, and it looks like `Y_is_Z` or `Y_match_Z`.  You can also use
(one or more) spaces (` `) instead of exactly one underscore (`_`) to
separate the words.

Available conditions:

* `Y_is_Z`: true if the variable Y equals Z case-sensitively.
* `Y_isnt_Z`: true if the variable Y doesn't equal Z case-sensitively.
* `Y_match_Z`: true if the variable Y is matched by the regular expression
in `Z`.  The regular expression is created case-sensitively.
* `Y_newer_or_Z`: true when variable Y is newer or equals (>=) to Z.
Variables are treated as versions.
* `Y_older_or_Z`: true when variable Y is older or equals (=<) to Z.
Variables are treated as versions.

A condition block is opened by the first `if`.  Later condition keys can
use `elsif` or `else` (or `if` to open a *new* condition block).

**Note**: `elsif` or `else` without an `if` will raise an exception.

Their behaviour is like in Crystal: `if` starts a condition block, `elsif`
starts an alternative condition block, and `else` is used if none of `if` or
`elsif` matched.  It's possible to mix condition key-values with normal
key-values.

**Note**: Conditions can be used in every *mapping*, even in *mappings* of
a conditional.  Each *mapping* acts as its own scope.

### Variables

Variables are set by the user of the class (probably through
`ConfigReader.from_yaml`).  All variable values are strings.

Variable names are **case-sensitive**.  A missing variable will be treated
as having an empty value (`""`).

### Examples

```yaml
foo: # A normal mapping
  bar: 1

# A condition: Matches if `platform` equals "arm".
if_platform_is_arm: # In Crystal: `if platform == "arm"`
  company: ARM et al

# You can mix in values between conditionals.  It won't "break" following
# elsif or else blocks.
not_a_condition: Hello

# An elsif: It matches if
# 1) the previous conditions didn't match, and
# 2) its own condition matches.
elsif_platform_match_x86: # In Crystal: `elsif platform =~ /x86/`
  company: Many different

# An else: Matches if all previous conditions didn't match.
else:
  company: No idea

# At any time, you can start a new if sequence.
"if today is friday": # You can use spaces instead of underscores too
  hooray: true
```

## Dependencies

To modularize the configuration, you can require ("merge") external yaml
files from within your configuration.

This is triggered by using a key named `<<`, and writing the file name as
value: `<<: my_dependency.yml`.  The file-extension can also be omitted:
`<<: my_dependency` in which case an `.yml` extension is assumed.

The dependency path is relative to the currently processed YAML file.

You can also require multiple dependencies into the same *mapping*:

```yaml
types:
  Something: true # You can mix dependencies with normal fields.
  <<: simple_types.yml
  <<: complex_types.yml
  <<: ignores.yml
```

The dependency will be embedded into the open *mapping*: It is transparent
to the client code.

It's perfectly possible to mix conditionals with dependencies:

```yaml
if_os_is_windows:
  <<: windows-specific.yml
```

### Errors

An exception will be raised if any of the following occur:

* The maximum dependency depth of `10` (`MAX_DEPTH`) is exceeded.
* The dependency name contains a dot: `../foo.yml` won't work.
* The dependency name is absolute: `/foo/bar.yml` won't work.

# Platform support

<!-- Table is sorted from A-Z ascending, versions descending. -->

| Arch   | System        | CI             | Clang version          |
| ------ | ------------- | -------------- | ---------------------- |
| arm64  | macOS         | GitHub Actions | Homebrew's latest      |
| x86_64 | Arch Linux    | GitHub Actions | Latest (shared)        |
| x86_64 | Debian 12     | *None*         | 14, 19, 22             |
| x86_64 | Ubuntu 24.04  | GitHub Actions | 14, 16, 18, 20, 22, 23 |
|        | Other systems | Help wanted    | ?                      |

LLVM and Clang 14 or newer and Crystal 1.8 or newer are required.

You require the LLVM and Clang development libraries and headers.  If you don't
have them already installed, bindgen will tell you. These packages are usually
named after the following pattern on Debian-based systems:
`clang-18 libclang-18-dev llvm-18 llvm-18-dev`.

On macOS, install them with Homebrew: `brew install llvm pcre2 bdw-gc`.
Homebrew's LLVM 23.1.0 can't be linked statically; run `brew upgrade llvm` to
get a newer one, or set `BINDGEN_DYNAMIC=1` to link the shared libraries.


# Contributing

1. Open a new issue on the project to discuss what you're going to do and possibly receive comments
2. Read the `STYLEGUIDE.md` for some tips.
3. Then do the rest, PR and all.  You know the drill :)

## Contributors

- [Papierkorb](https://github.com/Papierkorb) Stefan Merettig - creator
- [docelic](https://github.com/docelic) Davor Ocelic
- [kalinon](https://github.com/kalinon) Holden Omans
- [HertzDevil](https://github.com/HertzDevil) Quinton Miller
- [ZaWertun](https://github.com/ZaWertun) Yaroslav Sidlovsky

# License

This project (`bindgen`) and all of its sources, except those otherwise noted,
all fall under the `GPLv3` license.  You can find a copy of its complete license
text in the `LICENSE` file.

The configuration used to generate code, and all code generated by this project,
fall under the full copyright of the user of `bindgen`.  `bindgen` does not
claim any copyright, legal or otherwise, on your work.  Established projects
should define a license they want to use for the generated code and
configuration.
