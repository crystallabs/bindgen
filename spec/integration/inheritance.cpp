/* Note: Used by `inheritance_spec.cr` and `virtual_override_spec.cr`. */

struct Base {
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
