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

// Pointers to arrays are only supported for arrays of built-in types.
struct ArrayPointerMember {
  Point (*rows)[4];
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

// Bit-fields sharing their storage unit with another member.
struct BitFieldAfterMember {
  char c;
  unsigned bits : 3;
};

struct MemberAfterBitField {
  unsigned bits : 3;
  char c;
};

struct EnumBitField {
  Color color : 2;
};

// C++ functions can't name the anonymous type of `member`.
struct AnonymousBitFields {
  struct {
    unsigned bits : 3;
  } member;
};

// Only bit-fields of integer types and `bool` are supported.
struct WideCharBitField {
  wchar_t c : 8;
};

// Packed bit-fields are packed with the members after them bit by bit.
struct __attribute__((packed)) PackedBitFields {
  unsigned bits : 3;
};

// Crystal has no packing other than `@[Packed]` of structures.
#pragma pack(push, 2)
struct PackedTwo {
  char c;
  int i;
};
#pragma pack(pop)

union __attribute__((packed)) PackedUnion {
  char c[5];
  int i;
};

// A packing which doesn't move any member is fine.
#pragma pack(push, 2)
struct PackedNoEffect {
  char c;
  short s;
};
#pragma pack(pop)
