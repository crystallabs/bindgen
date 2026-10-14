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
