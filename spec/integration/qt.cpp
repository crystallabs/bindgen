// Allow these tests to run without a real Qt installation.  Provide mocks for
// those features we require.

#define signals public
#define Q_GADGET void qt_check_for_QGADGET_macro();
#define Q_OBJECT class QPrivateSignal { };

struct QMetaObject {
  struct Connection {
    // Do nothing.
  };
};

struct QObject {
  template< typename R, typename T, typename... Args, typename F >
  static QMetaObject::Connection connect(void *ptr, R (T::*func)(Args...), F delegate) {
    delegate(Args { }...); // Call back to Crystal

    return QMetaObject::Connection();
  }
};

// Test object conversion at Proc boundaries
struct Conv {
};

struct ConvCpp {
};

ConvCpp conv_from_cpp(const Conv &) {
  return { };
}

Conv conv_to_cpp(const ConvCpp &) {
  return { };
}

// On to the actual test classes:

// Tests signal/slots connection wrapping
class SomeObject {
  Q_OBJECT
public:
  int normalMethod() { return 1; }
  Conv convMethod() { return { }; }

signals:
  void stuffHappened() {
    // Empty.
  }

  void overloaded(int x) {
    // Empty.
  }

  void overloaded(bool y) {
    // Empty.
  }

  void overloaded(int x, bool y) {
    // Empty.
  }

  void privateSignal(QPrivateSignal) {
    // Empty.
  }

  void convSignal(const Conv &) {
    // Empty.
  }
};

// Tests Q_GADGET cleaning
class SomeGadget {
public:
  // The real Q_GADGET would do the `public:` switch itself.
  Q_GADGET
};
