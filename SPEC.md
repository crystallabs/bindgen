# Specification

This document specifies all rules bindgen uses to do conversions.  All have
an assigned paragraph number for easy referencing.

Rules **should** have one (or more) examples, showcasing its implications.

## §1. C/C++ Parsing

## §2. Crystal wrappers

### §2.1 Name rewriting

Methods for which no other sub-rule applies have their name underscored:
`addWidget() -> #add_widget`

#### §2.1.1 Getters

A getter method is a method which:

1. Returns something different than C++ `void`
2. Has no arguments
3. Starts with `get`

If those rules are fulfilled, then the `get` prefix is removed:
`getWindowTitle() -> #window_title`

This rule can be overriden by `§2.1.2 Boolean getters`.

#### §2.1.2 Boolean getters

A boolean getter is a method which:

1. Returns C++ `bool`
2. Has no arguments
3. Starts with `get` or `is` or `has`

If these rules are fulfilled, then:

* `get` prefix is removed: `getAwesome() -> #awesome?`
* `is` prefix is removed: `isEmpty() -> #empty?`
* `has` prefix is retained: `hasSpace() -> #has_space?`

#### §2.1.3 Setters

A setter is a method which:

1. Returns C++ `void`
2. Has exactly one argument
3. Starts with `set`

If these rules are fulfilled, then the `set` prefix is removed, and a Crystal
writer method is created: `setWindowTitle() -> #window_title=`

#### §2.1.4 Overloaded operators

An overloaded operator is a method which:

1. Is either a method, or a non-member function taking a wrapped type by lvalue
   reference in the first function parameter
2. Corresponds to a Crystal method in the table below

|C++ operator|Crystal method|
|-|-|
|`+()`, `-()`, `~()`|`operator` dropped|
|`++()`|`succ!`|
|`++(int)`|`post_succ!`|
|`--()`|`pred!`|
|`--(int)`|`post_pred!`|
|`!()`|`not`|
|`*()`|`deref`|
|`==(T)`, `!=(T)`, `<(T)`, `>(T)`, `<=(T)`, `>=(T)`|`operator` dropped|
|`+(T)`, `-(T)`, `*(T)`, `/(T)`, `%(T)`, `&(T)`, `|(T)`, `^(T)`, `<<(T)`, `>>(T)`|`operator` dropped|
|`+=(T)`|`add!(T)`|
|`-=(T)`|`sub!(T)`|
|`*=(T)`|`mul!(T)`|
|`/=(T)`|`div!(T)`|
|`%=(T)`|`mod!(T)`|
|`&=(T)`|`bit_and!(T)`|
|`|=(T)`|`bit_or!(T)`|
|`^=(T)`|`bit_xor!(T)`|
|`<<=(T)`|`lshift!(T)`|
|`>>=(T)`|`rshift!(T)`|
|`&&(T)`|`and(T)`|
|`||(T)`|`or(T)`|
|`[](T)`|`[](T)`|
|`()(*T)`|`call(*T)`|

Both `T` and the return type in the table can be any type; const-ness of the
operator is not considered.  Non-member operators are automatically converted
into methods in the wrapper classes.  Bindgen always uses the operators
directly, and never invokes them as regular method calls.

The following C++ operators are ignored: `=(T)`, `<=>(T)`, `&()`, `->()`,
`->*(T)`, `,(T)`, all conversion operators.

The following Crystal operators are overloadable, but unused by Bindgen:
`&+`, `&-`, `&+(T)`, `&-(T)`, `&*(T)`, `&**(T)`, `//(T)`, `===(T)`, `<=>(T)`,
`[]?(*T)`, `[]=(*T, U)`.

### §2.2 Arguments

#### §2.2.1 Conversion

A conversion from the wrapper towards the binding happens if any of:

* The `crystal_type` and the `binding_type` differs
* A `from_crystal` for the arguments type is configured
* A `converter` for the arguments type is configured

If a conversion happens, the precedence is as follows:

1. `from_crystal` is used if set
2. `converter` is used if set

Examples:

1. A type with both `from_crystal` and `converter` set would be wrapped
by using the `from_crystal` template: `my_from_crystal(arg_name)`.
2. A type with `converter` set would be wrapped by using the `converter` module:
   `MyConverter.unwrap(arg_name)`.

#### §2.2.2 Unnamed arguments

C++ allows the declaration of unnamed arguments, like this: `void foo(int)`.
To wrap these methods, such arguments are given a name like `unnamed_arg_X`,
where `X` is the zero-indexed index of the affected argument.

Given `void foo(int, int two, int)`, the generated wrapper prototype would look
like this: `foo(unnamed_arg_0 : Int32, two : Int32, unnamed_arg_2 : Int32)`.

#### §2.2.3 Argument renaming

If an argument has a name which is a reserved word in Crystal, it gets an
underscore (`_`) appended: `void foo(int next) -> foo(next_ : Int32)`.

### §2.3 Inheritance and abstract classes

Inheritance from wrapped C++ classes is replicated in Crystal.

For a C++ class to be used as base-class in the Crystal wrapper, all of these
have to be true:

1. The base-class is wrapped.
2. The base-class is publicly inherited.

#### §2.3.1 Single inheritance

The base-class is inherited in Crystal, mirroring the C++ definition.

```cpp
class Foo : public Bar { ... };
```

If both `Foo` and `Bar` are wrapped, the following wrapper will be generated:

```crystal
class Foo < Bar
  # ...
end
```

#### §2.3.2 Multiple inheritance

The Crystal wrapper class will inherit from the first of all base-classes.  All
following base-classes are wrapped through an `#as_X` conversion method.

```cpp
class Foo : public Bar, public AnotherOne { ... };
```

Will generate:

```crystal
class Foo < Bar
  def as_another_one : AnotherOne
    # Conversion code ...
  end

  # ...
end
```

#### §2.3.3 Abstract classes

An abstract C++ class will also be declared `abstract` in Crystal.  Further,
an implementation class is generated to aid in conversion calls later on:

```cpp
class Foo { // A pure class
  virtual void doSomething() = 0;
};
```

Will be wrapped as:

```crystal
abstract class Foo
  abstract def do_something
end

class FooImpl < Foo
  def do_something
    # Call implementation ...
  end
end
```

**Note**: The `Impl` class cannot be inherited from.

#### §2.3.4 Virtual method override

It's possible to override a C++ method in a Crystal sub-class, if the C++ method
was defined as `virtual`.  A Crystal method is considered to override a C++
virtual method if the Crystal method and the C++ method share the same name.

```cpp
class Foo {
public:
  virtual int doWork() = 0;
};
```

Can be overriden from Crystal like this:

```crystal
class MyFoo < Foo # Inherit
  def do_work
    # ...
  end
end
```

The arguments and result values are proxied back and forth from C++ like normal
wrappers do.  The rules of argument handling is the same.  Such overrides will
look and behave the same to C++ as any other virtual C++ method.

**Note**: Calling `super` in the body of a Crystal method that overrides a
concrete C++ virtual method is not supported.  **The process will crash due to
a stack overflow!**

#### §2.3.5 Base-class wrapper

A `Superclass` wrapper is defined for every impure abstract class in C++.  This
wrapper is returned by the `#superclass` method; both the type and the method
are private within the original Crystal wrapper.  Concrete virtual methods of
the C++ type are mirrored in the superclass wrapper, except these methods always
invoke the original C++ methods, ignoring method overrides from Crystal.

```cpp
class Foo {
public:
  virtual int bar(int x);
  virtual int baz(int x) = 0;
};
```

Will generate:

```crystal
class Foo
  private class Superclass
    def bar(x)
      # ...
    end
  end

  private def superclass : Superclass
    # ...
  end
end
```

This allows sub-classes of `Foo` to do the following:

```crystal
class MyFoo < Foo
  def bar(x)
    superclass.bar(x) + superclass.bar(x - 1)
    # equivalent to: super + super(x - 1)
  end
end
```

**Note**: The wrapped methods always refer to the C++ methods.  If another class
inherits from `MyFoo` and overrides `#bar`, the overriding method may refer to
`MyFoo#bar` using `super` directly.

### §2.4 Instance properties

Property methods can be generated for any static or instance variable in a
Crystal wrapper corresponding to a C++ `class`, `struct`, or `union`, if all of
the following criteria are met:

* The member's visibility is `public` or `protected` (the latter is mapped to
  `private` in Crystal)
* The member is not an lvalue or rvalue reference
* The type's `copy_structure` is not set
* The type's `instance_variable` settings do not reject the member
* The member is not inside a nested anonymous type that names another member
  (this is supported by §3.2.2)
* The member does not satisfy the requirements for wrapped static constants (see
  §2.4.5)
* The method is not a setter for a `const` member

The names of property methods are underscored according to the member name.

```cpp
struct Point {
  int xPos, yPos;
protected:
  const int version;
};
```

Will be wrapped as: (implementations omitted)

```crystal
class Point
  def x_pos : Int32 end
  def x_pos=(x_pos : Int32) : Void end
  def y_pos : Int32 end
  def y_pos=(y_pos : Int32) : Void end
  private def version : Int32 end
end
```

### §2.4.1 Class type properties

If a data member is a value of another wrapped type, the getter allocates a copy
of the variable in C/C++ (using the C++ type's copy constructor), so it is safe
to modify the returned object without altering the original value.

```cpp
struct Line {
  Point start;
};
```

```crystal
class Line
  def start : Point end
  def start=(start : Point) : Void end
end

def start_from_zero(line : Line)
  # This has no effect!
  # `line.start` returns a copy of the property
  line.start.x_pos = 0
end
```

### §2.4.2 Pointer properties

If a data member is a pointer to a wrapped type, instances of the wrapped type
can be passed to C++ directly without having to construct any pointers in
Crystal.  These properties may additionally be configured as nilable, in which
case they may accept and return `nil` as well, corresponding to C++'s `nullptr`.

```cpp
struct LinkedList {
  LinkedList *child;
  LinkedList *prev; // nilable
};
```

Generates:

```crystal
class LinkedList
  def child() : LinkedList end
  def child=(child : LinkedList) : Void end
  def prev() : LinkedList? end
  def prev=(child : LinkedList?) : Void end
end
```

Pointers of non-wrapped types, including primitive types, are exposed as Crystal
`Pointer(T)`s, and they are always nilable, using `Pointer(T).null` instead
of `nil`.

```cpp
struct OutParam {
  int *index;
  bool *found;
};
```

```crystal
class OutParam
  def index : Int32* end
  def index=(index : Int32*) : Void end
  def found : Bool* end
  def found=(found : Bool*) : Void end
end
```

### §2.4.3 Anonymous members

Properties inside nested anonymous types are allowed as long as they are
directly accessible from the instance's top level.

```cpp
struct Props {
  struct {
    int x, y; // accessible from top level
  } point; // not wrapped
  union {
    int foo;
    struct {
      char bar;
      char baz;
    };
  };
};
```

```crystal
class Props
  def foo : Int32 end
  def foo=(foo : Int32) : Void end
  def bar : Char end
  def bar=(bar : Char) : Void end
  def baz : Char end
  def baz=(baz : Char) : Void end
end
```

### §2.4.4 Static data members

Static variables have the wrapper class itself as the receiver.  The names for
constant member getters are still underscored, and their initializers are NOT
copied to the Crystal wrappers.

```cpp
struct Application {
  static Application *instance;
  static const int VERSION; // not defined
};
```

```crystal
class Application
  def self.instance : Application end
  def self.instance=(instance : Application) : Void end
  def self.version : Int32 end
end
```

### §2.4.5 Static constants

If a static variable additionally satisfies the following conditions, a wrapped
constant will be generated instead of a getter method:

* The member is `const` or `constexpr`
* The member's initializer is available in the parsed C++ sources
* The member is an integral, floating-point, or boolean value

```cpp
struct Application {
  static const int VERSION = 103;
  static constexpr double epsilon = 0.000001;
};
```

```crystal
class Application
  VERSION = 103
  EPSILON = 1.0e-6
end
```

### §2.5 Constructors

Bindgen copies the non-special constructors of each class to the corresponding
Crystal wrapper, provided they are accessible and not deleted.  Copy
constructors and move constructors are not copied.

```cpp
struct Foo {
  Foo();
  Foo(const Foo &);
  Foo(Foo &&);
  Foo(int) = delete;
};

class Bar {
  Bar();
};
```

generates

```crystal
class Foo
  def initialize() end
end

class Bar
  # `#initialize()` is not defined
end
```

### §2.5.1 Implicit constructors

Bindgen is able to generate default constructors for classes that are
default-constructible in C++ but have no user-provided constructors.

```cpp
struct Foo {
  int x;
};

struct Bar {
  int &x;
};
```

```crystal
class Foo
  def initialize() end
end

class Bar
  # `#initialize()` is not defined
end
```

### §2.5.2 Aggregate constructors

Wrapper classes that obey the following rules receive an aggregate constructor
where each field of the class is initialized by a named argument:

* The class contains at least 1 non-static data member.
* All fields of the class are public, non-anonymous members that do not have
  in-class default initializers.
* The class is not polymorphic.
* The class does not inherit from any other class.
* The class has no user-provided constructors.
* The class is not a C++ `union`.

```cpp
struct Point {
  int x;
  int y;
};
```

```crystal
class Point
  def initialize(*, x : Int32, y : Int32) end
end
```

### §2.6 Generic types

Only sequential container types are instantiated on the Crystal side, as if each
container implements the following interface:

```crystal
module Container(T)
  include Indexable(T)

  # All containers must be default-constructible
  # abstract def initialize

  abstract def unsafe_fetch(index : Int) : T
  abstract def push(value : T) : Void
  abstract def size : Int32

  def <<(x : T)
    push(x)
    self
  end

  def concat(values : Enumerable(T))
    values.each { |v| self << v }
    self
  end

  # Wrapper selection macro
  macro of(*type_args) end

  # General conversion method (§2.6.1)
  # abstract def self.from(values : Enumerable(T)) : Container(T)
end
```

Bindgen automatically collects all instantiations of each container type that
appear in method argument types or return types; explicit instantiations may be
configured with the `containers` section.  Aliases to complete container types
and container type arguments are both supported.

It is possible to store containers as Crystal instance variables using the
container module.  However, the generic module does not name the actual wrapper
type instantiated by Bindgen.  To do this, the `.of` macro should be used:

```crystal
class Foo
  # `Container(Int32)` is the module type
  # `Container.of(Int32)` produces the concrete, non-generic wrapper type
  # corresponding to the `Int32` instantiation
  # For all `T`, `Container.of(T) < Container(T)`, and no other types include
  # the same instantiated module
  @x : Container(Int32) = Container.of(Int32).new

  # Referring to a non-instantiated type is a compilation error
  # @x = Container.of(NoReturn).new

  # If the wrapper type is stored in a constant, it can be used in array literal
  # initializers
  BitArray = Container.of(Bool)
  SECRET = BitArray{true, false, false, true}

  # Type restrictions, like instance variables, can only use module types due to
  # grammar restrictions
  def matches_secret?(bits : Container(Bool))
    bits.to_a == SECRET.to_a
  end

  # Module types can be nested
  def transpose(ary : Container(Container(Float64)))
    Container.of(Container(Float64)).new
  end

  # One level of nested `Enumerable`s can be automatically wrapped in an array
  # literal initializer
  FloatMatrix = Container.of(Container(Float32))
  def skew(x : Float32, y : Float32, z : Float32)
    FloatMatrix{
      [0_f32,    -z,     y],
      [    z, 0_f32,    -x],
      [   -y,     x, 0_f32],
    }
  end
end
```

### §2.6.1 Automatic container conversion

Every container wrapper class defines a `.from` class method, which takes any
matching enumerable and converts it into that wrapper type.  Enumerables passed
to C++ are automatically converted using the same method.  In both cases, the
argument is reused if it is already of the wrapper type.

```cpp
struct Foo {
  static double sum(const Container<double> &values);
};
```

```crystal
class Foo
  def self.sum(values : Enumerable(Float64)) : Float64
    # converted = Container.of(Float64).from(values)
    # ...
  end
end

Foo.sum([1.2, 3.4]) # => 4.6
Foo.sum({1.2, 3.4}) # => 4.6

# No copies are generated
Foo.sum(Container.of(Float64).from [1.2, 3.4]) # => 4.6
```

## §3. Crystal bindings

### §3.1 Naming scheme

The bindings have to support method overloading, and as such use name mangling
to generate unique method names based on a method prototype.

The name consists out of the following parts (in this order):

1. `bg` prefix, marking it as bindgen wrapper function
2. The qualified C++ class name
3. Method type marker (See below)
4. The C++ method name
5. The mangled argument list (See below)

All of these parts are joined by a single underscore (`_`).

#### Argument type mangling

The argument list is a list of all types of the arguments, in the order they
appear in the method prototype.  Each argument types C++ name is taken and
transformed, such that:

1. A `*` is replaced with `X`
2. A `&` is replaced with `R`
3. All alpha-numeric characters are kept
4. All other characters are replaced with `_`

#### Method types

The method type marker mainly depends on the method type.  However, special
generated methods may use custom markers to distinguish them.

* Member methods don't have a marker
* Static methods use `STATIC`
* Property methods use either `GETTER` or `SETTER` (see §2.4)
* Constructors use `CONSTRUCT`
* Destructors use `DESTRUCT`
* Overloaded operators use `OPERATOR`, followed by a name that uniquely
  identifies the operator

#### Examples

1. Member method `void Foo::bar(int *&)` -> `bg_Foo_bar_int_XR`
2. Static method: `void Foo::bar(std::string)` ->
   `bg_Foo_STATIC_bar_std__string`
3. Method without arguments: `void Foo::bar()` -> `bg_Foo_bar_` (Trailing `_`)
4. Operator method: `bool Foo::operator==(const Foo &)` ->
   `bg_Foo__OPERATOR_eq_const_Foo_R`

### §3.2 Structures

Structures (`struct` / `union`) marked with `copy_structure` are available under
`lib Binding`.  Built-in types can be used directly, as are pointers to other
types.

```cpp
class Wrapper { }; // structure not copied

struct Point {
  int x, y;
  bool z;
  Wrapper *w;
  Point *p;
};

union Conv {
  int a;
  float b;
};
```

```crystal
lib Binding
  struct Point
    x : Int32
    y : Int32
    z : Bool
    w : Wrapper* # refers to the return value of `Wrapper#to_unsafe`
    p : Point*
  end

  union Conv
    a : Int32
    b : Float32
  end
end
```

#### §3.2.1 Name rewriting

The names of a struct and its enclosing namespaces are CamelCased, and then
joined together by underscores (`_`).

* `Point` → `Point`
* `foo_bar` → `FooBar`
* `MyLib::core::val_array` → `MyLib_Core_ValArray`

#### §3.2.2 Nested anonymous types

Unnamed structures nested inside another structure are also copied, provided
that the structure names a data member and the enclosing structure is also
copied.

```cpp
struct Outer {
  struct {
    int bar;
  } foo;
};

Outer { }.foo.bar; // => 0
```

```crystal
struct Outer
  foo : Outer_Unnamed0
end

struct Outer_Unnamed0
  bar : Int32
end

Binding::Outer.new.foo.bar # => 0
```

#### §3.2.3 Anonymous members

If the unnamed structure does not name a member, its contents are merged into
the enclosing type.  This is only done when the structures are both `struct`s or
both `union`s; otherwise, a unique member name is generated for the anonymous
member holding the structure.

```cpp
struct Outer {
  struct {
    int bar;
  };
  union {
    float baz;
    bool quux;
  };
};

Outer x;
x.bar; // => 0
x.quux; // => false
```

```crystal
struct Outer
  bar : Int32
  unnamed_arg_1 : Outer_Unnamed0
end

struct Outer_Unnamed0
  baz : Float32
  quux : Bool
end

x = Binding::Outer.new
x.bar # => 0
x.unnamed_arg_1.quux # => false
```

## §4. C++ wrapper functions

For each wrapped C++ function, there is at least one wrapper function generated.

## §5. Enumerations

### §5.1 Name rewriting

The name of an enum is constantized: `enum foo_bar` is translated as
`enum FooBar`.

### §5.2 Field name rewriting

The name of an enum constant is constantized: `color_0 -> Color0`.

### §5.3 Flag types

If an enumeration type is signaled to be a flags type, it'll get a `@[Flags]`
annotation in Crystal wrapper code.

Given a `QFlags<ApplicationFlag>`, the generated enumeration will look like

```cr
@[Flags]
enum ApplicationFlag : UInt32
  # Constants ...
end
```

### §5.4 Nested anonymous enums

An unnamed enumeration type inside a wrapped class will dump its enumerators
into the enclosing wrapper as constants, instead of generating an enumeration.
The underlying type of the enumeration type is respected.

```cpp
struct Calculator {
  enum { PLUS, MINUS, TIMES, DIVIDE };
};
```

```crystal
class Calculator
  Plus = 0u32
  Minus = 1u32
  Times = 2u32
  Divide = 3u32
end
```

## §Q. Qt specifics

### §Q.1 QObject signals

QObject signals are wrapped in two methods: First, the emission method, and
second the connection method, which are then exposed as Crystal wrappers.

* Given this signal: `void changed(int one)`
* Emission method: `changed(one : Int32) : Void`
* Connection method: `on_changed(&block : Int32 -> Void)`

### §Q.1.1 Signal connection object

The connection method returns an connection object, which responds to
`#disconnect`.  Calling this method breaks the connection.  Subsequent calls to
this method have no effect.

### §Q.1.2 Overloaded signals

An overload is defined for each signature of a connection method that may take
different sets of parameters.  The overloads take the expected types of the
signal parameters, as mandatory function arguments.  This only happens to
overloaded signals; type arguments are not required for signals with unique
signatures.

* Given these signals:
  * `void changed(int one)`
  * `void changed(bool two)`
* Connection methods:
  * `on_changed(type1 : Int32.class, &block : Int32 -> Void)`
  * `on_changed(type1 : Bool.class, &block : Bool -> Void)`

### §Q.2 QFlags

`QFlags<EnumT>` is a C++/Qt template type marking a C++ `enum` to be a flags
type.  Once detected, the `clang` tool will mark the `enum` type as a flags
type.  See `§5.3 Flag types`.
