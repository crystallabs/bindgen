#include <string>
#include <vector>
#include <algorithm>

// A container laid out like Qt's QList: The methods specific to one element
// type live in a template specialization the instantiation derives from.
template <typename T> struct ListSpecialMethods { };

template <typename T> class List;

template <> struct ListSpecialMethods<std::string> {
  std::string join(const std::string &separator) const;
  std::string longest() const;
  void sort();
};

template <typename T>
class List : public ListSpecialMethods<T> {
  friend struct ListSpecialMethods<T>;
  std::vector<T> m_items;

public:
  typedef T value_type;

  List() { }
  List(const std::vector<T> &items) : m_items(items) { }

  const T &at(int index) const { return m_items.at(index); }
  void push_back(const T &item) { m_items.push_back(item); }
  int size() const { return m_items.size(); }

  T first() const { return m_items.front(); }
  void clear() { m_items.clear(); }

  // Nested in the instantiation, like QList's iterators: Not wrapped.
  struct Cursor { int position; };
  Cursor cursor() const { return Cursor{ 0 }; }

  // Declared through the class-local typedef, like QList's takeFirst
  value_type take_last() {
    value_type item = m_items.back();
    m_items.pop_back();
    return item;
  }
};

using StringList = List<std::string>;

inline std::string ListSpecialMethods<std::string>::join(const std::string &separator) const {
  const StringList *self = static_cast<const StringList *>(this);
  std::string result;

  for (int i = 0; i < self->size(); i++) {
    if (i > 0) result += separator;
    result += self->at(i);
  }

  return result;
}

inline std::string ListSpecialMethods<std::string>::longest() const {
  const StringList *self = static_cast<const StringList *>(this);
  std::string result;

  for (int i = 0; i < self->size(); i++) {
    if (self->at(i).size() > result.size()) result = self->at(i);
  }

  return result;
}

inline void ListSpecialMethods<std::string>::sort() {
  StringList *self = static_cast<StringList *>(this);
  std::sort(self->m_items.begin(), self->m_items.end());
}

// A class deriving from a container instantiation, like Qt's QPolygon.
class Polygon : public List<int> {
public:
  Polygon() { }
  Polygon(const List<int> &sides) : List<int>(sides) { }

  int perimeter() const {
    int total = 0;
    for (int i = 0; i < size(); i++) total += at(i);
    return total;
  }
};

enum Color { Red, Green, Blue };

typedef List<double> DoubleList;

class Lists {
public:
  // A typedef of an instantiation is looked through without a rule, also
  // as a reference argument.
  DoubleList doubles() {
    return DoubleList(std::vector<double>{ 2.5, 3.5 });
  }

  double totalOf(const DoubleList &values) {
    double total = 0;
    for (int i = 0; i < values.size(); i++) total += values.at(i);
    return total;
  }

  // A container of an enum: Its wrapper names the enum, which may be written
  // later than the class.
  List<Color> colors() {
    return List<Color>(std::vector<Color>{ Red, Blue });
  }

  StringList names() {
    return StringList(std::vector<std::string>{ "Alice", "Bob" });
  }

  std::string joined(const StringList &list) {
    return list.join("+");
  }

  // Instantiated from its use only
  List<double> halves() {
    return List<double>(std::vector<double>{ 0.5, 1.5 });
  }

  int total(const List<int> &values) {
    int sum = 0;
    for (int i = 0; i < values.size(); i++) sum += values.at(i);
    return sum;
  }

  Polygon triangle() {
    return Polygon(List<int>(std::vector<int>{ 3, 4, 5 }));
  }

  int perimeter(const Polygon &polygon) {
    return polygon.perimeter();
  }
};

// A typedef'd container argument of a virtual method, like
// `QAbstractItemModel::mimeData(const QModelIndexList &)`.
struct Totals {
  virtual ~Totals() { }
  virtual double total(const DoubleList &values) {
    double sum = 0;
    for (int i = 0; i < values.size(); i++) sum += values.at(i);
    return sum;
  }

  double run() {
    return total(DoubleList(std::vector<double>{ 1.0, 2.0 }));
  }
};
