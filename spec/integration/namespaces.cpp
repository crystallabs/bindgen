// Class hierarchies going back and forth between namespaces.  A Crystal class
// must be defined after its superclass, so some namespaces have to be reopened
// in Crystal (#89).

namespace N {
  struct A {
    int a() { return 1; }
  };
}

struct B : N::A {
  int b() { return 2; }
};

namespace N {
  struct C : B {
    int c() { return 3; }
  };

  namespace M {
    struct D : C {
      int d() { return 4; }
    };
  }

  struct Abstract : M::D {
    virtual ~Abstract() { }
    virtual int pure() = 0;
  };
}

struct E : N::M::D {
  int e() { return 5; }
};

namespace N {
  namespace M {
    struct F : E {
      int f() { return 6; }
    };
  }

  struct G : M::F {
    int g() { return 7; }
  };
}

struct Concrete : N::Abstract {
  int pure() override { return 8; }
};

