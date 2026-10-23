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

#include <cstdlib>

// Owns its children like Qt's: The parent deletes them as it's destroyed.  The
// parent and the children refer to each other through memory of `malloc`, which
// the GC doesn't scan, like Qt's d-pointer.
struct QObject {
  QObject(QObject *parent = nullptr)
    : d(static_cast<Data *>(std::calloc(1, sizeof(Data)))) {
    setParent(parent);
  }

  // Not copyable, like by `Q_DISABLE_COPY`.
  QObject(const QObject &) = delete;
  QObject &operator=(const QObject &) = delete;

  virtual ~QObject() {
    ++destroyed_;
    setParent(nullptr);
    while (QObject *child = d->firstChild) {
      child->setParent(nullptr);
      delete child;
    }
    std::free(d);
  }

  void setParent(QObject *parent) {
    if (QObject *old = d->parent) {
      QObject **link = &old->d->firstChild;
      while (*link != this) link = &(*link)->d->nextSibling;
      *link = d->nextSibling;
    }

    d->parent = parent;
    d->nextSibling = nullptr;
    if (parent) {
      d->nextSibling = parent->d->firstChild;
      parent->d->firstChild = this;
    }
  }

  QObject *parent() const { return d->parent; }

  int childCount() const {
    int count = 0;
    for (QObject *child = d->firstChild; child; child = child->d->nextSibling) ++count;
    return count;
  }

  // Overridden from Crystal: The hook keeping the object alive and the one of
  // `VirtualOverride` setting its jump table both run in the constructor.
  virtual int kind() const { return 1; }
  int callKind() const { return kind(); }

  static void deleteObject(QObject *object) { delete object; }
  static int destroyed() { return destroyed_; }

  template< typename R, typename T, typename... Args, typename F >
  static QMetaObject::Connection connect(void *ptr, R (T::*func)(Args...), F delegate) {
    delegate(Args { }...); // Call back to Crystal

    return QMetaObject::Connection();
  }

private:
  struct Data {
    QObject *parent;
    QObject *firstChild;
    QObject *nextSibling;
  };

  Data *d;
  static int destroyed_;
};

int QObject::destroyed_ = 0;

// Like a `QLabel`: The parent isn't the first argument.
struct Label : QObject {
  Label(const char *text, QObject *parent = nullptr) : QObject(parent) { }
};

// Like a `QGraphicsItem`: Owned by its parent item, which isn't a `QObject`.
struct QGraphicsItem {
  QGraphicsItem(QGraphicsItem *parent = nullptr) { setParentItem(parent); }
  QGraphicsItem(const QGraphicsItem &) = delete;
  QGraphicsItem &operator=(const QGraphicsItem &) = delete;
  virtual ~QGraphicsItem() { }

  void setParentItem(QGraphicsItem *parent) { parent_ = parent; }

private:
  QGraphicsItem *parent_ = nullptr;
};

// Takes a `parent`, but isn't a `QObject`: Nothing owns it.
struct Unowned {
  Unowned(QObject *parent) { }
  void setParent(QObject *parent) { }
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

  void ignoredSignal(int) {
    // Empty.  Listed in `ignore_methods`.
  }
};

// Tests Q_GADGET cleaning
class SomeGadget {
public:
  // The real Q_GADGET would do the `public:` switch itself.
  Q_GADGET
};
