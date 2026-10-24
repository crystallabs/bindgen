# Specification

This document specifies all rules bindgen uses to do conversions.  All have
an assigned paragraph number for easy referencing.

Rules **should** have one (or more) examples, showcasing its implications.

## §1. C/C++ Parsing

### §1.1 Declared methods

The `declare_methods:` type rule adds methods the parser doesn't report, from
their C++ declarations: `QMenu *menu() const`, `void setMenu(QMenu *menu)`.
A template member instantiated by the call, like these in Qt 6, is bound this
way.  The methods are wrapped like any other, with named arguments and the
defaults Crystal can express.

## §2. Crystal wrappers

### §2.1 Name rewriting

Methods for which no other sub-rule applies have their name underscored:
`addWidget() -> #add_widget`

The `rename:` type rule names a method explicitly, by its C++ name, signature
or a regular expression over the signature like `ignore_methods`:
`rename: { raise: raise_ }`.  A renamed virtual method is overridden under
its Crystal name.

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

A pointer to a wrapped class accepts `nil` if it defaults to `nullptr` in
C++, or if the `nilable:` type rule lists the argument: `nilable: { setModel:
[0] }`.  `nil` reaches C++ as a null pointer.  The same rule makes a pointer
result `T?` or `T` regardless of `nilable_results`: `nilable: { menuBar:
false }`.

A copied structure passed by value (`copy_structure` with `pass_by: Value`,
like Qt's `QPoint`) taken by non-const reference or non-const pointer is
passed as a pointer to its storage, so the method writes into it: into the
object of a wrapper class hosting the structure, `stream >> point`, or into
the Crystal `struct` of a `kind: Struct` wrapper, which is taken by pointer
like a built-in type, `stream >> pointerof(point)`.  A pointer accepts `nil`
where the `nilable:` rule or a `nullptr` default says so.  Virtual methods
keep dropping such arguments, as a Crystal override would get a copy, and a
const pointer stays dropped.

A view type, like `QStringView`, converts like the type it views when its
rules build a temporary of that type for the call, which lives until the call
returns, and copy a result out of the view.  The `shadowed_by:` rule of the
view type drops an overload taking it where one taking the viewed type
exists, as both would take the same Crystal arguments.

#### §2.2.2 Unnamed arguments

C++ allows the declaration of unnamed arguments, like this: `void foo(int)`.
To wrap these methods, such arguments are given a name like `unnamed_arg_X`,
where `X` is the zero-indexed index of the affected argument.

Given `void foo(int, int two, int)`, the generated wrapper prototype would look
like this: `foo(unnamed_arg_0 : Int32, two : Int32, unnamed_arg_2 : Int32)`.

A virtual method's unnamed arguments take the names an override gives them:
Qt declares `QValidator::validate(QString &, int &)`, and
`QAbstractSpinBox::validate(QString &input, int &pos)`, so both wrappers, and
the abstract `def` a Crystal subclass implements, name them `input` and
`pos`.  Of several overrides naming an argument differently, the first wins.

#### §2.2.3 Argument renaming

If an argument has a name which is a reserved word in Crystal, it gets an
underscore (`_`) appended: `void foo(int next) -> foo(next_ : Int32)`.

#### §2.2.4 C arrays

A reference to a complete C array of built-in types is taken as a `Slice` of
the array's elements, which must have as many elements as the array.  If not,
an `ArgumentError` is raised.  A `StaticArray` is passed using `#to_slice`.
A returned reference to such an array becomes a `Slice` like an array member
(see §2.4.6).  An array argument which decays to a pointer is a pointer.

A pointer to such an array is a pointer to a `StaticArray`, also in instance
properties and copied structures.

A reference to an array of enums or of copied structures is a `Slice` of these,
like `Slice(Color)` or `Slice(Binding::Point)`.  A reference to a
one-dimensional array of a wrapped class is a `BindgenHelper::ArrayView` of
the wrapper class, see §2.4.6.  An `ArrayView` of the wrong size raises an
`ArgumentError`.

Methods using arrays of other types, multi-dimensional arrays of wrapped
classes, pointers to arrays of other than built-in types, or arrays of unknown
size are not wrapped.  Neither are virtual methods using arrays, unless they
are `final`.

```cpp
struct Foo {
  float trace(const float (&matrix)[3][3]);
  int (&values())[4];
  Bar (&bars())[2];
  int sum(const Bar (&bars)[2]);
  int first(const int list[4]); // Same as `const int *list`
  int sum(const int (*rows)[3], int count);
  int corner(int m[][3]); // Same as `int (*m)[3]`
};
```

```crystal
class Foo
  def trace(matrix : Slice(StaticArray(Float32, 3))) : Float32 end
  def values : Slice(Int32) end
  def bars : BindgenHelper::ArrayView(Bar) end
  def sum(bars : BindgenHelper::ArrayView(Bar)) : Int32 end
  def first(list : Int32*) : Int32 end
  def sum(rows : Int32[3]*, count : Int32) : Int32 end
  def corner(m : Int32[3]*) : Int32 end
end
```

#### §2.2.5 Out arguments

A method may write through an argument instead of, or next to, returning a
value: `QValidator::validate(QString &input, int &pos)` changes the input and
the cursor position, `QLockFile::getLockInfo(qint64 *pid, QString *host,
QString *app)` fills the pointers.  A non-const lvalue reference or a single
pointer to a type passed by value (`pass_by: Value`) and converted both ways by
`to_cpp` and `from_cpp`, like `QString`, `QByteArray`, `QVariant` or
`std::string`, is an *out argument*.  Such a type only exists in C++ as a
temporary made by its `to_cpp` template, so the C++ glue calls the method on a
local of the C++ type and hands the changed value back.  In a method having
one, a non-const reference or pointer to a built-in type or an enum, like
`int &` or `bool *`, is an out argument too; elsewhere it stays an `Int32*` or
`Bool*`.

A reference is an in/out argument: the wrapper takes it by value and returns
its new value.  A pointer is out-only: the wrapper takes no argument for it
and returns the value written.  A pointer defaulting to `nullptr` is still
out-only, the glue always passes a local.  The out values follow the method's
result:

* A method returning a value returns `{result, out1, out2, ...}`.
* A `void` method with one out argument returns that value alone.
* A `void` method with several returns `{out1, out2, ...}`.

```cpp
class Validator {
public:
  virtual State validate(QString &input, int &pos) const = 0;
  virtual void fixup(QString &input) const;
  bool info(qint64 *pid, QString *host, QString *app) const;
  static QString pick(const QString &caption, QString *selected = nullptr);
};
```

```crystal
class Validator
  abstract def validate(input : String, pos : Int32) : {Validator::State, String, Int32}
  def fixup(input : String) : String end
  def info : {Bool, Int64, String, String} end
  def self.pick(caption : String) : {String, String} end
end

state, input, pos = validator.validate("42", 0)
```

A Crystal override of a virtual method with out arguments (§2.3.4) returns the
same tuple, whose out values are written back into the C++ references, or
through the pointers unless they are null.  The abstract method of an abstract
class and the base-class wrapper (§2.3.5) have the wrapper's signature, so
`super` and `superclass.validate(input, pos)` return the tuple too.

Constructors never take out arguments: a pointer handed to a constructor is
usually kept, like `QTextStream(QString *)`, so they stay dropped.  So do the
setters of pointer members (§2.4.2), Qt signals and operators with such
arguments.  A method keeping the pointer beyond
the call, like `QTextStream::setString`, can't be told apart from one writing
through it: list it in `ignore_methods`.  Other indirections to a converted
type, like `const QString *`, `QString **` or `QString *&`, drop the method.

Of two overloads taking the same Crystal arguments, bindgen keeps the one with
more C++ arguments: the variant of `pick` taking `selected` too, which the
wrapper drops, replaces the variant ending before it, and a variant whose
further arguments have exposed defaults replaces a shorter one.

#### §2.2.6 `std::function` arguments

An argument of type `std::function<R (Args...)>`, by value or by reference,
written out or through a typedef like `QTextDocument::ResourceProvider`, is
taken as a `Proc(Args..., R)`: as a block if it is the last argument, as a
`Proc` argument otherwise, and in a setter (`setHandler(f)` is `#handler=`),
which can't take a block.  The arguments and the result are converted like
those of a Qt signal or a Crystal override: a `const std::string &` arrives
as a `String`, a `std::string` result is copied back.  A method returning a
`std::function`, or taking a bare function pointer, which can't carry a
closure, is skipped.  A virtual method taking a `std::function` is called
through the wrapper, but can't be overridden from Crystal; a pure one is
skipped.

```cpp
struct Button {
  void onClick(std::function<void ()> f);
  int each(int count, std::function<int (int, const std::string &)> f);
  void setFilter(const std::function<bool (int)> &f, int threshold);
};
```

```crystal
button.on_click { puts "clicked" }
button.each(3) { |index, name| index * 2 } # => 0 + 2 + 4
button.set_filter(->(value : Int32) { value.even? }, 10)
document.resource_provider = ->(url : Url) { Variant.new("resource") }
```

The C++ glue builds the `std::function` from a lambda calling the Crystal
`Proc`.  The lambda holds the proc in memory the GC scans but doesn't collect
(`bindgen_hold_proc` in `bindgen_helper.hpp`), freed with the last copy of
the `std::function`: the closure stays alive as long as C++ keeps the
function, wherever it stores it, and is collected once C++ drops it.  A block
runs on the thread calling it, so a function C++ calls from another thread,
like `QThreadPool::start`, has to be ignored (`ignore_methods`).

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

A virtual method marked `final` can't be overridden, and no method of a class
marked `final` can be overridden.

`super` in the body of a Crystal method that overrides a concrete C++ virtual
method calls the C++ implementation of the class the Crystal class derives
from: the wrapper method it reaches runs on an instance of a Crystal subclass,
which lacks the `BindgenWrapper` annotation of the generated classes, and
forwards to the base-class wrapper of `§2.3.5` instead of calling the virtual
method, which would re-enter the override.  A Crystal subclass not overriding
the method calls the C++ implementation the same way.  A wrapper of the
generated class itself, like one a getter returned, calls the virtual method,
and so reaches the Crystal override of the object's class.

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
    super + superclass.bar(x - 1)
    # `super` is `superclass.bar(x)`, whose arguments are all mandatory
  end
end
```

**Note**: The wrapped methods always refer to the C++ methods.  If another class
inherits from `MyFoo` and overrides `#bar`, `super` in the overriding method
refers to `MyFoo#bar`, as in any Crystal class.  The base-class wrapper of a
method `superclass_ignore_methods` leaves out isn't reached by `super`, which
then calls the virtual method.

#### §2.3.6 Casting

Wrapped classes related through inheritance get a `#to?(T.class)` method,
casting to the wrapper class `T`:

* To its own class, it returns `self`.
* To a further base-class of multiple inheritance, it calls `#as_X`.
* To a sub-class, if both are polymorphic (declare or inherit a virtual
  method), it does a `dynamic_cast` in C++ and returns `T?`: `nil` if the
  object isn't a `T`.  The result wraps the same C++ object.
* Anything else is passed on to `#to?` of the Crystal base-class, if any.
  Casting to an unrelated type is a compile-time error.

```cpp
struct Bar { virtual ~Bar(); static Bar *create(); };
struct Foo : Bar { };
```

```crystal
Bar.create.to?(Foo) # => #<Foo:...>, or nil
Foo.new.to?(Bar)    # => The same Foo
```

**Note**: A downcast returns a new instance of a wrapper class, even if the
object was created by a Crystal sub-class of `T`.  `T` must be a wrapper
class, not a Crystal sub-class of one.

#### §2.3.7 Type discovery

A pointer or reference to a polymorphic class is wrapped in the wrapper class
of the object's dynamic type, the most derived one the binding knows, so a
method declared to return a `Bar *` returns a `Foo` for an object created as
one.  This applies to the results of methods, to the arguments of callbacks
(the Crystal override of a virtual method, the block of a Qt signal) and to
`#to?`; a value, like a `Bar` returned by value, is of the class declared.

```cpp
struct Bar { virtual ~Bar(); static Bar *create(); static Bar copy(); };
struct Foo : Bar { int foo(); };
struct Hidden : Foo { }; // Not wrapped
```

```crystal
Bar.create.class  # => Foo, for an object created as a Foo or a Hidden
Bar.copy.class    # => Bar
Foo.bg_discover(pointer) # Wraps a `Binding::Foo*` the same way
```

The discovery looks the `typeid` of the object up in a table of the wrapped
classes inheriting from the declared class in Crystal (§2.3.1: the first
wrapped base, not the further ones), and walks their `dynamic_cast`s once for
a type the table doesn't have, like `Hidden`, remembering the class found.  An
object of a class the binding doesn't know is wrapped in the nearest wrapped
class.  A pointer to a class without wrapped sub-classes, or to a
non-polymorphic class, is wrapped in the class declared without a lookup, and
so is every pointer if the C++ code is built without RTTI.

An object constructed from Crystal comes back as the Crystal object which
constructed it, an instance of a Crystal sub-class included, with its instance
variables: the object remembers the Crystal object
(`BindgenHelper.set_crystal_object`, called by the constructors) and every
wrapper class has the discovery, polymorphic or not.  The reference is weak:
once the Crystal object is unreachable the GC clears it, and the object gets
a new wrapper.  A pointer to a secondary base (§2.3.2) or to a member of the
object, which the Crystal object doesn't wrap, and a copy get a new wrapper
too.

```crystal
class MyFoo < Foo
  property note = ""
end

mine = MyFoo.new
mine.note = "kept"
container.add(mine)
container.first.should be(mine)           # The same object
container.first.as(MyFoo).note # => "kept"
```

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
* The method is not a setter for a `const` member or a C array
* If the member is a C array, it is a complete array of C/C++ built-in types

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

### §2.4.6 Array properties

Getters are generated for complete C arrays of built-in types, which return
`Slice`s instead of Crystal `Array`s.  The `Slice`s are marked as read-only if
the array member is `const`.  Multi-dimensional arrays are also supported.
Arrays of enums and of copied structures are `Slice`s of these too.

A one-dimensional array of a wrapped class returns a
`BindgenHelper::ArrayView` of the wrapper class.  It's an `Indexable` view of
the C++ array: Its elements are wrappers referring to the array's elements,
not copies of them, so changes to them are visible in C++.  This differs from
class-type value members, whose getter returns a copy.  Assigning an element
through `#[]=` copies the value with the C++ copy-assignment operator.  It
raises if the array is `const` (see `#read_only?`), or if the class can't be
copy-assigned.

No setters are generated for array members.

```cpp
struct Foo {
  int bar[15][20][25];
  void *baz[8];
  const float quux[2];
  Foo *children[3];
  Bar bars[2];
};
```

```crystal
class Foo
  def bar : Slice(Int32[25][20]) end
  def baz : Slice(Void*) end
  def quux : Slice(Float32) end # read_only: true
  def bars : BindgenHelper::ArrayView(Bar) end

  # `#children` is not defined
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
* The class has no user-declared constructors.  This includes those declared as
  `= default` or `= delete`: They're allowed in an aggregate up to C++17, but
  not since C++20.
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

Sequential and associative container types are instantiated on the Crystal
side.  Each sequential container behaves as if it implements the following
interface:

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

Each associative container, like `std::map`, behaves like a `Hash`, as if it
implements the following interface (§2.6.2):

```crystal
module Map(K, V)
  include Enumerable({K, V})

  # All containers must be default-constructible
  # abstract def initialize

  abstract def [](key : K) : V # Raises `KeyError` if there's no such key
  abstract def []?(key : K) : V?
  abstract def []=(key : K, value : V) : V
  abstract def has_key?(key : K) : Bool
  abstract def delete(key : K) : V?
  abstract def size : Int32
  abstract def each(& : {K, V} ->)

  abstract def keys : Array(K)
  abstract def values : Array(V)

  def concat(pairs : Enumerable({K, V}))
    pairs.each { |k, v| self[k] = v }
    self
  end

  # Wrapper selection macro
  macro of(*type_args) end

  # General conversion method (§2.6.1)
  # abstract def self.from(pairs : Enumerable({K, V})) : Map(K, V)
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

Associative containers are converted from any `Enumerable` of key-value tuples,
like a `Hash`: `Map.of(String, Int32).from({"a" => 1})`.

### §2.6.2 Associative containers

Lookups never let a C++ exception escape: `#[]` and `#[]?` first check the key
through the container's `count` method, and then read the value through
`find`.  Neither `at()`, which throws, nor `operator[]`, which requires a
default constructible value type, is used.  `#[]=` replaces an existing value.

C++ iterators can't be passed to Crystal, and pointing into a container which
is changed during the iteration is undefined behaviour.  Thus `#each` copies all
entries into a `BindgenMapEntries`, and yields the entries of that copy by
index.  Iteration takes linear time, and changing the container during it is
safe.  It yields the entries the container had when the iteration began.

```crystal
map = Map.of(Int32, String).from({1 => "One", 2 => "Two"})
map.each do |key, value|
  map.delete(key + 1)   # `{2, "Two"}` is still yielded
  map[key * 10] = value # Not yielded
end
map.to_h # => {1 => "One", 10 => "One", 20 => "Two"}
```

### §2.6.3 Optional types

An optional, like `std::optional<T>`, converts to and from a `T?`, the value
or `nil`, when listed in `containers` with the type `Optional`: a method
returning one returns the value or `nil`, and one taking it accepts either.
The wrapper class is only seen when built directly, through `Optional.of(T)`
or `.from(value)`; it has `#has_value?`, `#to_nilable` and `#value=`.

```cpp
std::optional<QFont> displayFont();
int value_or(const std::optional<int> &value, int fallback);
```

```crystal
def display_font : Font? end
def value_or(value : Int32?, fallback : Int32) : Int32 end
```

### §2.6.4 Sets

A set, like `std::set<T>` or `QSet<T>`, is wrapped as an `Enumerable(T)`
with `#includes?`, `#add`/`#<<`, `#delete`, `#concat`, `#size` and `#empty?`,
a subset of `Set`, when listed in `containers` with the type `Set`.  A method
taking a set accepts any `Enumerable` of the element type, as for a
sequential container, and `Set.of(T).from(values)` builds one directly.
There is no index access: `#each` copies the elements into a
`BindgenSetElements` first, like §2.6.2's iteration, so changing the set
during it is safe.  The container's `insert`, `count` and `erase` methods are
named by `push_method`, `count_method` and `erase_method`: `contains` and
`remove` for a `QSet`.

```crystal
tags = item.tags           # A QSet<QString>, an Enumerable(String)
tags.includes?("new")      # => true
tags << "seen"
item.tags = ["a", "b"]     # Any Enumerable
```

### §2.6.5 Class template instantiations

An instantiation of a class template listed in `classes:` is wrapped like any
other class, with the template arguments substituted.  It's known by the
configured name however it's spelled in C++, also through a `typedef`, so
methods using it are wrapped.

```cpp
template<typename T, int N>
struct Array {
  T at(int index) const;
};

typedef Array<int, 3> Triple;

struct Factory {
  Triple make();
};
```

```yaml
classes:
  "Array<int, 3>": IntArray3
```

```crystal
class IntArray3
  def at(index : Int32) : Int32
end

Factory.new.make # => IntArray3
```

The binding type is named after the C++ type, here `Binding::ArrayInt3`.

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
* Connection method: `on_changed(type : Qt::ConnectionType = Qt::ConnectionType::AutoConnection, &block : Int32 -> Void)`

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
* Connection methods, with the type arguments before the connection type:
  * `on_changed(type1 : Int32.class, type : Qt::ConnectionType = Qt::ConnectionType::AutoConnection, &block : Int32 -> Void)`
  * `on_changed(type1 : Bool.class, type : Qt::ConnectionType = Qt::ConnectionType::AutoConnection, &block : Bool -> Void)`

### §Q.1.3 Connection type and context

The connection method takes the `Qt::ConnectionType` of `QObject::connect`,
`Qt::AutoConnection` by default.  The `Qt::ConnectionType` enum must be
wrapped, under `enums:`.  The context object of the connection is the
application, `QCoreApplication::instance()`, or the sender while there is no
application.  With an automatic connection, a signal emitted in the thread of
the application runs the block at once, and one emitted in another thread
queues the block to the application's event loop: Crystal code only runs in
the main thread.  `Qt::DirectConnection` runs the block on the emitting
thread, whichever it is.

* `thread.on_finished { }`: Queued to the main thread, the thread emits it
* `button.on_clicked(Qt::ConnectionType::QueuedConnection) { }`: Run by the
  event loop, after the emission returns

### §Q.1.4 Exceptions in the block

An exception the block raises is handed to `BindgenHelper.on_exception`, and
the signal's emission returns as if the block had returned: a Crystal
exception can't unwind through the C++ frames emitting the signal.  The same
applies to a Crystal override of a virtual method, which returns a zero of its
result type to C++ then.

### §Q.2 QFlags

`QFlags<EnumT>` is a C++/Qt template type marking a C++ `enum` to be a flags
type.  Once detected, the `clang` tool will mark the `enum` type as a flags
type.  See `§5.3 Flag types`.

### §Q.3 Hash and string conversion

A class with a `qHash` method, bound from the free `qHash(const T &, size_t)`
by `member_functions: [qHash]`, gets `#hash(hasher)` forwarding to it, so its
instances are `Hash` keys and `Set` elements, equal by `operator==`.  A class
with a `toString()` method taking no mandatory argument gets `#to_s(io)`
writing it, and `#inspect(io)` writing `#<Qt::Date 2024-01-15>`.
