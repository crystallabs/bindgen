// Standalone test of assets/bindgen_qt_meta.hpp against a real Qt, without Crystal:
// the tables, reflection, properties, invoking by name, connecting by name and by
// index, queued delivery, and a chained meta-object.  Not part of `crystal spec`.
//
// Qt 6 (Homebrew frameworks):
//   clang++ -std=c++17 -fPIC -Iassets -I/opt/homebrew/include -F/opt/homebrew/lib -framework QtCore \
//     -L/opt/homebrew/lib -lgc -lgccpp spec/manual/qt_meta_runtime_test.cpp -o /tmp/meta_test6 && /tmp/meta_test6
// Qt 5:
//   clang++ -std=c++17 -fPIC -Iassets -I/opt/homebrew/include -F/opt/homebrew/opt/qt@5/lib -framework QtCore \
//     -L/opt/homebrew/lib -lgc -lgccpp spec/manual/qt_meta_runtime_test.cpp -o /tmp/meta_test5 && /tmp/meta_test5

#include <QtCore/QCoreApplication>
#include <QtCore/QMetaMethod>
#include <QtCore/QMetaProperty>
#include <QtCore/QVariant>
#include <cstdio>
#include "bindgen_qt_meta.hpp"

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %d: %s\n", __LINE__, #cond); ++failures; } } while (0)

// Mimics BgInherit_QObject.
struct Counter : QObject {
  BindgenQtMetaObject *bgMeta = nullptr;
  int value = 42;
  int mode = 1; // Of the "Crystal enum" Mode: Fast = 1, Slow = 2
  int increments = 0;
  int lastEmitted = -1;

  const QMetaObject *metaObject() const override { return bgMeta ? bgMeta->metaObject() : QObject::metaObject(); }
  void *qt_metacast(const char *n) override { return bgMeta && n && bgMeta->isClassName(n) ? this : QObject::qt_metacast(n); }
  int qt_metacall(QMetaObject::Call c, int id, void **a) override {
    id = QObject::qt_metacall(c, id, a);
    if (id < 0 || !bgMeta) return id;
    return bgMeta->metacall(this, this, c, id, a); // The Crystal object is the object itself here
  }
};

// The "Crystal" side.  Methods, signals first: 0 valueChanged, 1 renamed, 2 modeChanged, 3 increment, 4 add.
// Properties: 0 value, 1 name, 2 mode.
static void metacall(void *crystal, int call, int id, void **argv) {
  Counter *c = static_cast<Counter *>(crystal);
  if (call == 0) {
    if (id == 3) {
      ++c->increments;
      ++c->value;
      BindgenQtArg a{0, &c->value};
      bindgen_qt_activate(c, c->bgMeta, 0, &a, 1);
    } else if (id == 4) {
      int a = *static_cast<int *>(argv[1]);
      CrystalString b = bindgen_qt_string_at(argv[2]);
      int r = a + b.size;
      if (argv[0]) *static_cast<int *>(argv[0]) = r;
    }
  } else if (call == 1) {
    if (id == 0) *static_cast<int *>(argv[0]) = c->value;
    else if (id == 1) bindgen_qt_set_string(argv[0], CrystalString{"named", 5});
    else if (id == 2) *static_cast<int *>(argv[0]) = c->mode;
  } else if (call == 2) {
    if (id == 0) c->value = *static_cast<int *>(argv[0]);
    else if (id == 2) c->mode = *static_cast<int *>(argv[0]);
  }
}

static int received = -1;
static void onValueChanged(void **argv) { received = *static_cast<int *>(argv[1]); }
static int receivedMode = -1;
static void onModeChanged(void **argv) { receivedMode = *static_cast<int *>(argv[1]); }

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);

  BindgenQtMetaObject *meta = bindgen_qt_meta_new("Counter");
  const char *t1[] = {"int"}; const char *n1[] = {"value"};
  CHECK(bindgen_qt_meta_add_method(meta, 0, "valueChanged", "void", 1, t1, n1) == 0);
  const char *t2[] = {"QString", "QObject*"}; const char *n2[] = {"name", "by"};
  CHECK(bindgen_qt_meta_add_method(meta, 0, "renamed", "void", 2, t2, n2) == 1);
  CHECK(bindgen_qt_meta_add_method(meta, 1, "increment", "void", 0, nullptr, nullptr) == 2);
  const char *t3[] = {"int", "QString"}; const char *n3[] = {"a", "b"};
  CHECK(bindgen_qt_meta_add_method(meta, 1, "add", "int", 2, t3, n3) == 3);
  const char *t4[] = {"Counter::Mode"}; const char *n4[] = {"mode"};
  CHECK(bindgen_qt_meta_add_method(meta, 0, "modeChanged", "void", 1, t4, n4) == 4);
  CHECK(bindgen_qt_meta_add_property(meta, "value", "int", 0, true, false) == 0);
  CHECK(bindgen_qt_meta_add_property(meta, "name", "QString", -1, false, false) == 1);
  CHECK(bindgen_qt_meta_add_property(meta, "mode", "Counter::Mode", 2, true, true) == 2); // Notified by signal 2, once the signals are first
  const char *keys[] = {"Fast", "Slow"}; const int values[] = {1, 2};
  CHECK(bindgen_qt_meta_add_enum(meta, "Mode", false, 2, keys, values) == 0);
  BindgenQtMetacall proc;
  proc.withoutSelf = &metacall;
  proc.self = nullptr;
  bindgen_qt_meta_finish(meta, nullptr, proc);

  Counter obj;
  obj.bgMeta = meta;
  meta->setSuperdata(&QObject::staticMetaObject);

  const QMetaObject *mo = obj.metaObject();
  CHECK(std::strcmp(mo->className(), "Counter") == 0);
  CHECK(mo->superClass() == &QObject::staticMetaObject);
  CHECK(mo->methodCount() == QObject::staticMetaObject.methodCount() + 5);
  CHECK(mo->propertyCount() == QObject::staticMetaObject.propertyCount() + 3);
  int sig = mo->indexOfSignal("valueChanged(int)");
  CHECK(sig == mo->methodOffset());
  CHECK(mo->indexOfSignal("renamed(QString,QObject*)") == mo->methodOffset() + 1);
  CHECK(mo->indexOfSignal("modeChanged(Counter::Mode)") == mo->methodOffset() + 2);
  CHECK(mo->indexOfSlot("increment()") == mo->methodOffset() + 3);
  CHECK(mo->indexOfSlot("add(int,QString)") == mo->methodOffset() + 4);
  QMetaMethod add = mo->method(mo->methodOffset() + 4);
  CHECK(add.methodType() == QMetaMethod::Slot);
  CHECK(add.parameterCount() == 2);
  CHECK(add.parameterNames().at(1) == "b");
  CHECK(add.parameterType(0) == QMetaType::Int);
  CHECK(add.parameterType(1) == QMetaType::QString);
  CHECK(add.returnType() == QMetaType::Int);
  CHECK(std::strcmp(add.typeName(), "int") == 0);
  QMetaMethod renamed = mo->method(mo->methodOffset() + 1);
  CHECK(renamed.parameterType(1) == QMetaType::QObjectStar);
  CHECK(renamed.methodType() == QMetaMethod::Signal);
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
  CHECK(add.returnMetaType() == QMetaType::fromType<int>());
  CHECK(add.parameterMetaType(1) == QMetaType::fromType<QString>());
  CHECK(mo->method(mo->methodOffset() + 3).returnMetaType() == QMetaType::fromType<void>());
#endif

  // Properties
  int pi = mo->indexOfProperty("value");
  CHECK(pi == mo->propertyOffset());
  QMetaProperty vp = mo->property(pi);
  CHECK(vp.isWritable());
  CHECK(vp.hasNotifySignal());
  CHECK(vp.notifySignalIndex() == sig);
  CHECK(std::strcmp(vp.typeName(), "int") == 0);
  CHECK(obj.property("value").toInt() == 42);
  CHECK(obj.setProperty("value", 7));
  CHECK(obj.value == 7);
  CHECK(obj.property("name").toString() == "named");
  CHECK(!mo->property(pi + 1).isWritable());
  CHECK(obj.property("value").toInt() == 7);

  // The enumerator and the registered enum type
  CHECK(mo->enumeratorCount() == 1);
  QMetaEnum me = mo->enumerator(mo->indexOfEnumerator("Mode"));
  CHECK(me.isValid());
  CHECK(std::strcmp(me.name(), "Mode") == 0);
  CHECK(me.keyCount() == 2);
  CHECK(me.keyToValue("Slow") == 2);
  CHECK(std::strcmp(me.valueToKey(1), "Fast") == 0);
  CHECK(me.isScoped() && !me.isFlag());
  int modeType = bindgen_qt::type_id("Counter::Mode");
  CHECK(modeType >= QMetaType::User);
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
  QMetaType modeMeta = QMetaType::fromName("Counter::Mode");
  CHECK(modeMeta.flags() & QMetaType::IsEnumeration);
  CHECK(modeMeta.sizeOf() == sizeof(int));
  CHECK(modeMeta.metaObject() == mo);
  CHECK(me.metaType() == modeMeta || bindgen_qt::Revision < 12);
#else
  CHECK(QMetaType::typeFlags(modeType) & QMetaType::IsEnumeration);
  CHECK(QMetaType::metaObjectForType(modeType) == mo);
#endif
  QMetaProperty mp = mo->property(mo->indexOfProperty("mode"));
  CHECK(mp.isEnumType() && !mp.isFlagType());
  CHECK(mp.enumerator().isValid() && std::strcmp(mp.enumerator().name(), "Mode") == 0);
  CHECK(std::strcmp(mp.typeName(), "Counter::Mode") == 0);
  CHECK(mp.notifySignalIndex() == mo->methodOffset() + 2);
  QVariant modeValue = obj.property("mode");
  CHECK(modeValue.userType() == modeType);
  CHECK(modeValue.toInt() == 1);
  CHECK(modeValue.toString() == "Fast");
  CHECK(obj.setProperty("mode", "Slow"));
  CHECK(obj.mode == 2);
  CHECK(obj.setProperty("mode", 1));
  CHECK(obj.mode == 1);
  CHECK(obj.setProperty("mode", modeValue) && obj.mode == 1);
  CHECK(!obj.setProperty("mode", "Nowhere"));
  QMetaMethod modeChanged = mo->method(mo->indexOfSignal("modeChanged(Counter::Mode)"));
  CHECK(modeChanged.isValid());
  CHECK(modeChanged.parameterType(0) == modeType);
  CrystalProc<void, void **> modeSlot;
  modeSlot.withoutSelf = &onModeChanged;
  modeSlot.self = nullptr;
  QMetaObject::Connection *modeConn = bindgen_qt_connect(&obj, bindgen_qt_signal_index(meta, 2), Qt::QueuedConnection, modeSlot);
  CHECK(modeConn && *modeConn);
  int newMode = 2;
  BindgenQtArg modeArg{0, &newMode};
  bindgen_qt_activate(&obj, meta, 2, &modeArg, 1);
  CHECK(receivedMode == -1);
  QCoreApplication::processEvents();
  CHECK(receivedMode == 2); // The registered type is queued

  // Invoke by name
  CHECK(QMetaObject::invokeMethod(&obj, "increment"));
  CHECK(obj.increments == 1 && obj.value == 8);
  int r = 0;
  CHECK(QMetaObject::invokeMethod(&obj, "add", Q_RETURN_ARG(int, r), Q_ARG(int, 2), Q_ARG(QString, QString("xyz"))));
  CHECK(r == 5);

  // Connect a proc to the Crystal signal, then emit
  CrystalProc<void, void **> slot;
  slot.withoutSelf = &onValueChanged;
  slot.self = nullptr;
  QMetaObject::Connection *conn = bindgen_qt_connect(&obj, bindgen_qt_signal_index(meta, 0), 0, slot);
  CHECK(conn && *conn);
  int v = 99;
  BindgenQtArg a{0, &v};
  bindgen_qt_activate(&obj, meta, 0, &a, 1);
  CHECK(received == 99);
  QObject::disconnect(*conn);
  received = -1;
  bindgen_qt_activate(&obj, meta, 0, &a, 1);
  CHECK(received == -1);

  // Connect by name to a Crystal slot of another object
  Counter target;
  target.bgMeta = meta;
  CHECK(QObject::connect(&obj, SIGNAL(valueChanged(int)), &target, SLOT(increment())));
  bindgen_qt_activate(&obj, meta, 0, &a, 1);
  CHECK(target.increments == 1);
  // Emitting a signal by name goes through metacall and activates
  CHECK(QMetaObject::invokeMethod(&obj, "valueChanged", Q_ARG(int, 3)));
  CHECK(target.increments == 2);
  // The string signal, with a QString temporary
  CrystalString name{"hello", 5};
  BindgenQtArg args[] = {{1, &name}, {0, nullptr}};
  QObject *who = &obj;
  args[1].pointer = &who;
  bindgen_qt_activate(&obj, meta, 1, args, 2);
  // Queued delivery to the proc from the main thread's loop
  conn = bindgen_qt_connect(&obj, bindgen_qt_signal_index(meta, 0), Qt::QueuedConnection, slot);
  received = -1;
  bindgen_qt_activate(&obj, meta, 0, &a, 1);
  CHECK(received == -1);
  QCoreApplication::processEvents();
  CHECK(received == 99);

  // A chained Crystal subclass
  BindgenQtMetaObject *child = bindgen_qt_meta_new("Child");
  const char *tc[] = {"double"}; const char *nc[] = {"x"};
  bindgen_qt_meta_add_method(child, 0, "moved", "void", 1, tc, nc);
  bindgen_qt_meta_finish(child, meta, proc);
  Counter kid;
  kid.bgMeta = child;
  const QMetaObject *km = kid.metaObject();
  CHECK(km->superClass() == meta->metaObject());
  CHECK(km->indexOfSignal("moved(double)") == meta->metaObject()->methodCount());
  CHECK(km->indexOfSlot("increment()") == mo->methodOffset() + 3);
  CHECK(kid.property("value").toInt() == 42);
  CHECK(QMetaObject::invokeMethod(&kid, "increment") && kid.increments == 1);
  CHECK(kid.inherits("Counter"));
  CHECK(kid.inherits("Child"));
  CHECK(kid.qt_metacast("Counter") == &kid);

  std::printf("%s: %d failures (revision %u, Qt %s)\n", failures ? "FAILED" : "OK", failures, bindgen_qt::Revision, qVersion());
  return failures;
}
