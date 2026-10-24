#include <string>

/* Out arguments: a converted value type, `std::string` here, taken by
 * non-const reference or by pointer.  The wrapper returns the values written
 * back with its result.  See `Parser::Method#out_arguments`. */

// A class whose default `Flavor()` isn't exposed to Crystal, unlike `nullptr`.
struct Flavor {
  int value;
  Flavor(int v = 0) : value(v) { }
};

class Outs {
  std::string m_name;

public:
  Outs() : m_name("outs") { }

  // In/out reference, void: the wrapper returns the string alone.
  void shout(std::string &text) {
    text += "!";
  }

  // Out pointer, void: the wrapper takes no argument and returns the string.
  void name(std::string *out) const {
    *out = m_name;
  }

  // Non-void with an in/out reference and a built-in in/out reference, which
  // is one too in this method: `{result, text, pos}`.
  int validate(std::string &text, int &pos) {
    pos += 1;
    text = "valid " + text;
    return static_cast<int>(text.size());
  }

  // Out pointers defaulting to `nullptr`, one of a built-in type: the glue
  // always passes a local.
  bool info(std::string *host, int *pid = nullptr) const {
    if (host) *host = "localhost";
    if (pid) *pid = 42;
    return true;
  }

  // Two out pointers, void: a tuple without a result.
  void split(const std::string &input, std::string *head, std::string *tail) const {
    size_t pos = input.find(',');
    *head = input.substr(0, pos);
    *tail = pos == std::string::npos ? "" : input.substr(pos + 1);
  }

  // An out pointer with a default after a non-exposed one: the variant
  // taking it replaces the one just shorter, which takes the same wrapper
  // arguments, and the one with the exposed default after it replaces both.
  std::string pick(int index, const Flavor &flavor = Flavor(), std::string *selected = nullptr, int options = 0) {
    if (selected) *selected = std::to_string(flavor.value) + std::to_string(options);
    return "picked " + std::to_string(index);
  }

  // Without `builtin_out_arguments`, a pointer to a built-in type stays a
  // pointer in a method without a converted out argument...
  int plainPointer(int *value) const {
    *value += 1;
    return *value;
  }

  // ...unless an `out_arguments` entry says so.
  int forced(int *value) const {
    *value = 7;
    return 1;
  }

  // Stay dropped: not a single indirection to a value, or const.
  void droppedPointerToPointer(std::string **text) { }
  void droppedConstPointer(const std::string *text) { }
  void droppedReferenceToPointer(std::string *&text) { }
};

// A constructor keeps dropping a pointer to a converted type: it usually
// keeps the pointer, like `QTextStream(QString *)`.
class Keeper {
  std::string *m_target;

public:
  Keeper() : m_target(nullptr) { }
  Keeper(std::string *target) : m_target(target) { }

  int value() const { return m_target ? 2 : 1; }
};

// Virtual methods with out arguments, overridden in Crystal and called from
// C++: the override returns the tuple, which is written back.
class Transformer {
public:
  virtual ~Transformer() { }

  virtual int transform(std::string &text, int &count) {
    text = "C++ " + text;
    count += 10;
    return 1;
  }

  virtual void describe(std::string *out) const {
    *out = "base";
  }

  std::string runTransform(const std::string &input, int count) {
    std::string text = input;
    int result = transform(text, count);
    return text + "/" + std::to_string(count) + "/" + std::to_string(result);
  }

  std::string runDescribe() const {
    std::string text;
    describe(&text);
    return text;
  }

  // A null out pointer: the override's value is dropped.
  void describeNowhere() const {
    describe(nullptr);
  }
};

// Pure virtuals with out arguments, implemented in Crystal, or in C++ behind
// the `Impl` class.
class AbstractFormatter {
public:
  virtual ~AbstractFormatter() { }

  virtual void format(std::string &text) = 0;
  virtual std::string prefix(std::string *suffix) const = 0;

  std::string run(const std::string &input) {
    std::string text = input;
    format(text);
    return text;
  }

  std::string runPrefix() const {
    std::string suffix;
    std::string prefix = this->prefix(&suffix);
    return prefix + suffix;
  }
};

class UpperFormatter : public AbstractFormatter {
public:
  void format(std::string &text) override {
    for (auto &c : text) c = static_cast<char>(toupper(c));
  }

  std::string prefix(std::string *suffix) const override {
    *suffix = "s";
    return "p";
  }
};

struct Formatters {
  static AbstractFormatter *upper() { return new UpperFormatter(); }
  static std::string run(AbstractFormatter *formatter, const std::string &input) {
    return formatter->run(input);
  }
};
