struct Point {
  int x, y;

  Point(int x, int y) : x(x), y(y) { }
};

template<typename T>
struct Box {
  T value;

  Box(T v) : value(v) { }

  T get() const { return value; }
  void set(T v) { value = v; }

  static int count() { return sizeof(T); }
};

bool operator==(const Box<int> &a, const Box<int> &b) { return a.value == b.value; }

// Non-type template parameter
template<typename T, int N>
class Array {
public:
  Array() {
    for (int i = 0; i < N; i++) m_data[i] = T();
  }

  int size() const { return N; }
  T at(int index) const { return m_data[index]; }
  void set(int index, T value) { m_data[index] = value; }

  T sum() const {
    T total = T();
    for (int i = 0; i < N; i++) total += m_data[i];
    return total;
  }

private:
  T m_data[N];
};

// Default template argument
template<typename T, typename Factor = double>
struct Scaled {
  T base;
  Factor factor = 2;

  T scaled() const { return static_cast<T>(base * factor); }
};

// Negative and boolean non-type template arguments
template<int N, bool Twice>
struct Offset {
  int apply(int x) const { return Twice ? x + 2 * N : x + N; }
};

typedef Box<int> IntBox;

// Inherits from an instantiation
class Counter : public Box<int> {
public:
  Counter() : Box<int>(0) { }

  void increment() { set(get() + 1); }
};

class BoxFactory {
public:
  Box<int> make(int v) const { return Box<int>(v); }
  Box<int> *makePointer(int v) const { return new Box<int>(v); }
  IntBox makeTypedef(int v) const { return IntBox(v); }

  int unbox(const Box<int> &box) const { return box.get(); }
  int unboxPointer(Box<int> *box) const { return box->get(); }
  int unboxPoint(Box<Point> box) const { return box.value.x + box.value.y; }

  Array<int, 3> triple() const {
    Array<int, 3> a;
    a.set(0, 1); a.set(1, 2); a.set(2, 3);
    return a;
  }

  Box<Box<int>> nested(int v) const { return Box<Box<int>>(Box<int>(v)); }

  Scaled<int> scaled(int v) const { Scaled<int> s; s.base = v; return s; }

  Offset<-2, true> offset() const { return Offset<-2, true>(); }

  // Not configured, so it's skipped.
  Box<double> unknown() const { return Box<double>(1.5); }
};

// A typedef naming an instantiation, like Qt's `QMatrix3x3`: configured by
// the typedef's name.
typedef Array<float, 2> FloatPair;

bool operator==(const FloatPair &a, const FloatPair &b) { return a.at(0) == b.at(0) && a.at(1) == b.at(1); }

// A member class template, like `QCborStreamReader::StringResult<T>`.
struct Reader {
  template<typename T>
  struct Result {
    T data;
    int status;
  };

  Result<int> read() const { return Result<int>{7, 1}; }
  FloatPair pair() const { FloatPair p; p.set(0, 1.5f); p.set(1, 2.5f); return p; }
  Array<float, 2> spelledOut() const { return pair(); }
};
