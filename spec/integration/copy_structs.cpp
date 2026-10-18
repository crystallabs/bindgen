/* Note: Used by `copy_structs_spec.cr` and `instance_properties_spec.cr`. */

#include <string>
#include <cstddef>

struct Point {
  Point(int x, int y) : x(x), y(y) { }

  int x, y;

  static const int DIMENSIONS = 2;
};

struct Line {
  Point v1, v2;
};

struct PolyLine {
  Line *line;
  PolyLine *before, *after;
};

// `std::string` is converted, so a pointer to it is a raw pointer.
struct StringPointer {
  std::string *name;
  Point *point;
};

struct Nested {
  struct Inner {
    float a;
  };
  struct Inner2 {
    float b;
  } c;
};

struct Anonymous {
  struct {
    struct {
      int x0; // .x0
    };
    struct {
      int x1; // .p0.x1
    } p0;
  };
  struct {
    struct {
      int x2; // .p2.x2
    };
    struct {
      int x3; // .p2.p1.x3
    } p1;
  } p2;

  // Declares the implicit `operator=` of the anonymous struct, which is
  // wrapped under the typedef naming the struct in C++.
  void copyFrom(const Anonymous &other) { p2 = other.p2; }
};

// these fields should not be copied
struct Wrapped {
  struct {
    int x;
  };
  struct {
    int y;
  } z, z2;
  union {
    int i;
    float f;
  } u;
};



// Wrapped under another name in Crystal.
struct RenameMe {
  struct {
    int y;
  } z;
};

union PlainUnion {
  int x;
  float y;
};

// A union with a non-trivial destructor, which has to be run by the GC.
static int managedUnionsAlive = 0;

union ManagedUnion {
  int x;
  float y;

  ManagedUnion(int value) : x(value) { managedUnionsAlive++; }
  ~ManagedUnion() { managedUnionsAlive--; }

  static int alive() { return managedUnionsAlive; }
};

// neither union should be inlined
struct UnionInStruct {
  union {
    char a;
    int b;
  } u;
  union {
    float c;
    bool d;
  };
};

// neither struct should be inlined
union StructInUnion {
  struct {
    char a;
    int b;
  } s;
  struct {
    float c;
    bool d;
  };
};

// c and d can be inlined
union NestedUnion {
  union {
    char a; // .u.a
    int b; // .u.b
  } u;
  union {
    float c; // .c
    bool d; // .d
  };
};


// `Point` has a constructor, so it isn't POD, and a packed structure wouldn't
// pack it on most targets.
struct PlainPoint {
  int x, y;
};

// A packed structure, whose members aren't aligned.
struct __attribute__((packed)) Packed {
  char c;
  int i;
  PlainPoint p;
};

// A structure with a packed anonymous member, which isn't inlined.
struct PackedMember {
  char c;
  struct __attribute__((packed)) {
    char d;
    int i;
  };
};

// The C++ layout, to compare with the `lib struct`s.
int packed_size() { return sizeof(Packed); }
int packed_offset_i() { return offsetof(Packed, i); }
int packed_offset_p() { return offsetof(Packed, p); }
int packed_member_size() { return sizeof(PackedMember); }
int packed_sum(Packed value) { return value.c + value.i + value.p.x + value.p.y; }

class Props {
public:
  Props(int x, int y) :
    x_pub(x), y_pub(y),
    x_prot(x + 100), y_prot(y + 100),
    x_priv(x + 200), y_priv(y + 200)
  {
    (void)x_priv; // silence -Wunused-private-field
    (void)y_priv;

    v[2] = 2001;
    v2[4][3][2] = 2002;
  }

  int x_pub;
  const int y_pub;
  unsigned bits : 3;
  Point *position_ptr = new Point(12, 34);
  Point position_val {13, 35};

  int v[4] = { };
  bool flags[2] = { false, true };
  int v2[5][6][7] = { };
  const int v_c[8] = {2003};
  int *v_ptr[9] = { };
  int *v2_ptr[10][11] = { };

  Point points[2] = {Point(0, 0), Point(0, 0)};
  Point *points_ptr[2];

  std::string name_val = "props";
  std::string *name_ptr = &name_val;
  std::string *nameAddress() { return name_ptr; }

  static Point corner;
  static const Point origin;
  static constexpr float c_f32 = 1.2;
  static const bool c_b = true;

protected:
  int x_prot;
  const int y_prot;

private:
  int x_priv;
  const int y_priv;
};

Point Props::corner = Point(800, 600);
const Point Props::origin = Point(0, 0);

// The methods win over the property methods of `drop_action`.
class Clashing {
public:
  int dropAction() const { return drop_action + 1; }
  void setDropAction(int a) { drop_action = a * 2; }

protected:
  int drop_action = 0;
};

template<typename T>
struct Holder {
  T *ptr = nullptr;
};

// Members and methods of unknown template instantiations are ignored.
class TemplateMembers {
public:
  Holder<Point> pub_holder;
  Holder<Point> holder() { return pub_holder; }

protected:
  Holder<Point> d_ptr;
};

class NestedProtected {
protected:
  struct {
    int x;
  };
};

class NestedPrivate {
  struct {
    int x;
  };
};

struct ConfigIgnoreAll {
  const int a, b;
};

struct ConfigIgnore {
  const int a, b;
};

struct ConfigRename {
  const int m_iVar, m_iAnotherVar, x;
};

// The defaulted constructor makes this no aggregate in C++20.
struct ConfigNilable {
  ConfigNilable() = default;

  bool *bool_ptr;
  Point *point_ptr;
};
