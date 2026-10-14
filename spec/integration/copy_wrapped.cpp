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
