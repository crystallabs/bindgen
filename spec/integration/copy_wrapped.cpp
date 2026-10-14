// Copied structures which also have a wrapper class.

// An aggregate.
struct Pod {
  int a;
  int b;
};

// A structure with constructors and methods.
struct Vec {
  int x, y;

  Vec() : x(0), y(0) { }
  Vec(int x, int y) : x(x), y(y) { }

  int sum() const { return x + y; }
  void scale(int factor) { x *= factor; y *= factor; }

  Vec plus(Vec other) const { return Vec(x + other.x, y + other.y); }
  Vec plusRef(const Vec &other) const { return Vec(x + other.x, y + other.y); }
  Vec plusPtr(const Vec *other) const { return Vec(x + other->x, y + other->y); }
  void addTo(Vec *target) const { target->x += x; target->y += y; }
  void addToRef(Vec &target) const { target.x += x; target.y += y; }

  static Vec unit() { return Vec(1, 1); }
};

// A structure with members of another copied structure.
struct Segment {
  Vec from;
  Vec to;

  Vec delta() const { return Vec(to.x - from.x, to.y - from.y); }
};

// A class using the copied structures.
class VecUser {
  Vec m_vec;
  Pod m_pod;

public:
  VecUser() : m_vec(3, 4), m_pod{5, 6} { }

  Vec vec() const { return m_vec; }
  const Vec &vecRef() const { return m_vec; }
  Vec *vecPtr() { return &m_vec; }
  void setVec(Vec vec) { m_vec = vec; }

  Pod pod() const { return m_pod; }
  void setPod(const Pod &pod) { m_pod = pod; }
  int podSum(Pod pod) const { return pod.a + pod.b; }
};

Pod pod_swapped(Pod pod) {
  return Pod{pod.b, pod.a};
}

// Copied structures of different ABI classes, passed by value to and from
// virtual methods.
struct Triple {
  int a, b, c;
};

struct Duo {
  double x, y;
};

struct Wide {
  long long a, b, c;
};

class Transformer {
public:
  virtual ~Transformer() { }

  virtual Triple triple(Triple t, int n) { return Triple{t.a + n, t.b + n, t.c + n}; }
  virtual Duo duo(int n, Duo d) { return Duo{d.x * n, d.y * n}; }
  virtual Wide wide(Wide w, int n) { return Wide{w.a - n, w.b - n, w.c - n}; }

  Triple callTriple(Triple t, int n) { return triple(t, n); }
  Duo callDuo(int n, Duo d) { return duo(n, d); }
  Wide callWide(Wide w, int n) { return wide(w, n); }
};
