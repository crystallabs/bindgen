#include <string>

/* Note: Used by `inheritance_spec.cr` and `virtual_override_spec.cr`. */

struct Base {
  // A virtual operator, like `QTableWidgetItem::operator<`
  virtual bool operator<(const Base &other) const {
    return false;
  }

  bool lessThan(const Base &other) const {
    return *this < other;
  }

  virtual int calc(int a, int b) {
    return a + b;
  }

  virtual int randomNumber() {
    return 4; // chosen by fair dice roll.
              // guaranteed to be random.
  }

  Base *belongToUs() {
    return this;
  }
};

struct AbstractThing {
  int value = 1;

  virtual const char *name() const = 0;

  virtual int virtualInAbstractThing() {
    return 2;
  }

  int normalMethodInAbstractThing() {
    return this->value;
  }

  virtual int privatelyOverridden() { return 5; }

  // Overloads only differing in constness are wrapped once.
  int constOverload() { return 3; }
  int constOverload() const { return 4; }

  int callVirtualInAbstractThing() {
    return this->virtualInAbstractThing();
  }

  AbstractThing *itself() {
    return this;
  }
};

// An abstract class deriving from an abstract class: The `Impl` class of the
// middle one needs the overloads of the inherited pure method too.
struct AbstractScaler {
  virtual ~AbstractScaler() { }
  virtual int scaled(int a, int factor = 2) const = 0;
  // A default Crystal can't express: The overload without it is concrete.
  static int defaultPad() { return 2; }
  virtual int padded(int pad = defaultPad()) const = 0;
};

struct AbstractScalerMiddle : public AbstractScaler {
  virtual int extra() const = 0;
};

struct ConcreteScaler : public AbstractScalerMiddle {
  int scaled(int a, int factor) const override { return a * factor; }
  int padded(int pad) const override { return pad; }
  int extra() const override { return 7; }
};

struct ScalerFactory {
  static AbstractScalerMiddle *make() { return new ConcreteScaler(); }
};

// A base overriding a pure method privately, like `QAbstractListModel::parent`:
// Callers reach it through the base it is public in, and a subclass can still
// override it, but can't call it through `#superclass`.
struct AbstractShape {
  virtual ~AbstractShape() { }
  virtual int sides(int scale = 1) const = 0; // Split by its default argument
  virtual int area() const = 0;
  int corners() const { return sides(); }
};

struct AbstractRound : public AbstractShape {
private:
  int sides(int scale) const override { return 0 * scale; }
};

struct Circle : public AbstractRound {
  int area() const override { return 28; }
};

struct Shapes {
  static AbstractRound *round() { return new Circle(); }
  static int sidesOf(const AbstractShape &shape) { return shape.sides(); }
};

// An abstract class with an implicit default constructor and a virtual
// destructor, like `QItemEditorCreatorBase`: A Crystal subclass constructs it.
struct AbstractCreator {
  virtual ~AbstractCreator() { }
  virtual int make() const = 0;
};

// A method re-exported from a private base by a using-declaration, like
// `QRecursiveMutex::lock` in Qt 5.
struct Locker {
  int lock() { return 7; }
  int unlock() { return 8; }
};

struct Recursive : private Locker {
  using Locker::lock;
};

struct Subclass : public Base, public AbstractThing {
  int calc(int a, int b) override {
    return a * b;
  }

private:
  // Can only be called through `AbstractThing`.
  int privatelyOverridden() override { return 6; }

public:

  // We don't override Base::randomNumber here.

  const char *name() const override {
    return "Hello";
  }

  int callVirtual(int a, int b) {
    return this->calc(a, b);
  }

  int normalMethod() {
    return 1;
  }
};

struct Implicit : public Base {
  // We don't override Base::calc here.

  int callVirtual(int a, int b) {
    return this->calc(a, b);
  }
};

struct FinalClass final : public Base {
  int calc(int a, int b) override {
    return a - b;
  }
};

struct FinalMethod : public Base {
  int calc(int a, int b) final {
    return a - b;
  }

  int callVirtual(int a, int b) {
    return this->calc(a, b);
  }

  int callRandomNumber() {
    return this->randomNumber();
  }
};

struct Skip {
  virtual int ignoreThis() const {
    return 7;
  }
};



struct Super1 { };

namespace Module {
  struct Derived1 : Super1 { };
  struct Super2 { };
}

struct Derived2 : Module::Super2 { };

namespace Module {
  struct Super3 { };
  struct Derived3 : Super3 { };

  struct SuperV {
    virtual ~SuperV() { }
    virtual void f() { }
  };
}

// Downcasting.  `Animal` is abstract, `Dog` is the Crystal superclass of
// `Puppy`, and `Hamster` can also be cast to from its secondary base `Pet`.
struct Animal {
  virtual ~Animal() { }
  virtual int legs() const = 0;

  static Animal *create(int kind);
};

struct Dog : Animal {
  int legs() const override { return 4; }
  int fetch() { return 1; }
};

struct Puppy final : Dog {
  int fetch() { return 2; }
};

struct Pet {
  virtual ~Pet() { }
  int owner() { return 3; }
};

struct Hamster : Animal, Pet {
  int legs() const override { return 4; }
  int wheel() { return 5; }
};

Animal *Animal::create(int kind) {
  switch (kind) {
  case 0: return new Dog;
  case 1: return new Puppy;
  default: return new Hamster;
  }
}

struct Overloads {
  virtual int f(int) { return 1; }
  virtual int f(double) { return 2; }

  virtual int g() { return 3; }
  virtual int g() const { return 4; }

  virtual int h(int) { return 5; }
  int h(bool) { return 6; }

  int callFInt() { return this->f(0); }
  int callFDouble() { return this->f(0.0); }
  int callG() { return this->g(); }
  int callGConst() const { return this->g(); }
  int callHInt() { return this->h(0); }
  int callHBool() { return this->h(false); }
};

struct Grandparent {
  virtual int inGrandparent() { return 7; }

  int callInGrandparent() { return this->inGrandparent(); }
};

// Abstract through the pure `name()` of its second base, like `QLayout`.
struct AbstractSecond : public Base, public AbstractThing { };

// Abstract through a pure method of its base's base, like
// `QAbstractGraphicsShapeItem`.
struct PureGrandparent {
  virtual ~PureGrandparent() { }
  virtual int pure() = 0;
};

struct AbstractMiddle : PureGrandparent { };

struct AbstractLeaf : AbstractMiddle { };

// The override doesn't name its argument.
struct NamedArgument {
  virtual int named(int value) { return value; }
  virtual int unnamed(int) { return 2; }
};

struct UnnamedArgument : NamedArgument {
  int named(int) override { return 1; }
  int unnamed(int value) override { return value; }
};

struct Parent : Grandparent { };

struct Child : Parent { };

// All virtual methods are filtered, leaving an empty jumptable.
struct IgnoredByConfig { };

struct OnlyFilteredVirtuals {
  virtual void take(IgnoredByConfig *) { }
  int value() { return 8; }
};

// The vtable pointer of `Polymorphic` comes first, so `NonPolymorphic` isn't at
// offset 0, and can't be the Crystal superclass.
struct NonPolymorphic {
  int x = 11;
  int read() { return x; }
};

struct Polymorphic : NonPolymorphic {
  virtual ~Polymorphic() { }
  virtual int f() { return 1; }
};

// A nested class with a wrapped base.
struct Outer {
  struct Inner : Base {
    int inner() { return 12; }
  };
};

/* Covariant return types: `Square::clone` overrides `Shape::clone`. */
struct Shape {
  virtual ~Shape() { }
  virtual Shape *clone() const { return new Shape(); }
  virtual int sides() const { return 0; }
};

struct Square : Shape {
  Square *clone() const override { return new Square(); }
  int sides() const override { return 4; }
};

// A structure argument of a callback is passed by pointer, see
// `TypeHelper#proc_by_pointer?`: Larger than 16 bytes, the C ABI passes it
// indirectly, which a Crystal `Proc` taking it by value reads as garbage.
struct Triple {
  long a;
  long b;
  long c;
};

struct Summer {
  virtual ~Summer() { }
  virtual long sum(Triple triple) { return triple.a + triple.b + triple.c; }
  virtual long sumRef(const Triple &triple) { return triple.a + triple.b + triple.c; }

  long callSum() {
    Triple triple { 1, 2, 3 };
    return sum(triple);
  }

  long callSumRef() {
    Triple triple { 4, 5, 6 };
    return sumRef(triple);
  }
};

// A pure virtual method taking an ignored type can't be wrapped, so the class
// isn't sub-classed from Crystal: The C++ subclass would stay abstract.
struct Hidden { };

struct Painter {
  virtual ~Painter() { }
  virtual void draw(Hidden hidden) = 0;
  virtual int id() { return 1; }
};

struct SolidPainter : public Painter {
  void draw(Hidden hidden) override { }
};

/* An override without the default argument of the overridden method, like
 * `QGraphicsTextItem::paint` dropping the `widget = nullptr` of the pure
 * `QGraphicsItem::paint`.  C++ takes the default from the static type. */
struct Named {
  Named(int value) : value(value) { }
  int id() const { return value; }
  int value;
};

struct Greeter {
  virtual ~Greeter() { }
  virtual int greet(Named *who = nullptr) { return who ? who->id() : -1; }
};

struct PoliteGreeter : Greeter {
  int greet(Named *who) override { return who ? who->id() * 10 : -10; }
};

struct AbstractGreeter {
  virtual ~AbstractGreeter() { }
  virtual int greet(Named *who = nullptr) = 0;
  int greetNobody() { return greet(); }
};

struct OtherBase {
  virtual ~OtherBase() { }
  int other = 3;
};

// The pure method comes from the second base, like `QGraphicsObject`.
struct GreeterObject : public OtherBase, public AbstractGreeter { };

struct TextGreeter : public GreeterObject {
  int greet(Named *who) override { return who ? who->id() * 100 : -100; }
};

// A virtual method returning an enum, overridden in Crystal: the `Proc`
// passes the enum to C++ as is.
enum class Mood { Happy, Sad };

struct Moody {
  virtual ~Moody() { }
  virtual Mood mood() const { return Mood::Happy; }
  Mood ask() const { return mood(); }
};
