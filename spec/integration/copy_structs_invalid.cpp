/* Structures which can't be copied into a `lib struct`. */

#include <string>
#include <vector>

struct Opaque;

class Wrapped {
public:
  int value;
};

struct Point {
  int x, y;
};

enum Color {
  Red,
  Green,
};

// All of these members are fine.
struct Valid {
  int number;
  Color color;
  Point point;
  Point *point_ptr;
  Wrapped *wrapped_ptr;
  const char *c_string;
  void *anything;
  int numbers[4];
};

struct StringMember {
  int id;
  std::string name;
};

// Would be a `CrystalString`, which isn't a pointer.
struct StringPointerMember {
  std::string *name;
};

struct ContainerMember {
  std::vector<std::string> mount_options;
};

struct InstantiatedContainerMember {
  std::vector<int> numbers;
};

struct WrappedMember {
  Wrapped wrapped;
};

struct WrappedArrayMember {
  Wrapped wrapped[2];
};

struct UnknownPointerMember {
  Opaque *opaque;
};

union ContainerUnion {
  int id;
  std::vector<int> numbers;

  ContainerUnion() : id(0) { }
  ~ContainerUnion() { }
};

// An alias of a built-in type, configured as such.
typedef bool flag_t;

struct AliasMember {
  flag_t flag;
};

// A structure holding a reference can't be laid out in Crystal.
struct ReferenceMember {
  int &value;
};

// A pointer to an array is laid out as one pointer, not as an array.
struct ArrayPointerMember {
  int (*rows)[4];
};

// Structures which can't be copied byte-wise.
struct CopyConstructor {
  int value;

  CopyConstructor(const CopyConstructor &other) : value(other.value) { }
};

struct Destructor {
  int value;

  ~Destructor() { }
};

struct VirtualMethod {
  int value;

  virtual int get() const { return value; }
};

// The members of the base class aren't laid out like a C structure would be.
struct Derived : Point {
  int z;
};
