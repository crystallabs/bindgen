#include <cstdint>

enum TopLevel {
  A,
  b = A,
  c_c = -1,
};

namespace NS1 {
  enum InnerEnum { X };

  namespace NS2 {
    enum InnerEnum2 { X };
  }
}

enum U8Enum : uint8_t {
  D,
  E = (uint8_t)-1,
};



template <typename T>
class QFlags { };

enum FlagEnum {
  None = 0x00,
  P = 0x01,
  Q = 0x04,
  R = 0x0C,
};

template class QFlags<FlagEnum>;
typedef QFlags<FlagEnum> Flags;

// Nothing instantiates these flags, like Qt's `QMessageBox::Options`.
enum class ScopedFlag {
  S = 0x01,
  T = 0x02,
};

typedef QFlags<ScopedFlag> ScopedFlags;



struct Nested {
  enum { X = 10, Y = 20 };
};

struct Renamed {
  enum { Z = 30 };
};

// `None` and `All` of a flags enum are Crystal's own; an `All` of another
// value, like `QStyle::SC_All`, is renamed.
namespace Masks {
  enum MaskFlag {
    None = 0,
    Low = 1,
    High = 2,
    All = 3,
  };

  typedef QFlags<MaskFlag> MaskFlags;
}

namespace Odds {
  enum OddFlag {
    Odd = 1,
    All = 0,
  };

  typedef QFlags<OddFlag> OddFlags;
}
