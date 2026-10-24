#include <vector>
#include <string>
#include <map>
#include <unordered_map>
#include <optional>
#include <set>

typedef std::vector<unsigned char> bytearray;
typedef std::map<std::string, int> phonebook;
typedef unsigned int rgb;

class Point; // See below, for the optional of it

// An alias template, like Qt's `QPair`: The parser names the aliased type.
template <typename A, typename B> using couple = std::pair<A, B>;

// An ignored type: The container of it isn't instantiated.
enum class Secret { Hidden };

class Containers {
public:
  std::vector<Secret> secrets() { return { Secret::Hidden }; }

  // Pairs are converted to and from tuples.
  std::pair<std::string, int> entry() {
    return { "one", 1 };
  }

  int sum(const std::pair<int, int> &values) {
    return values.first + values.second;
  }

  std::vector<std::pair<std::string, int>> entries() {
    return { { "a", 1 }, { "b", 2 } };
  }

  // The pair appears only inside the list.
  std::vector<std::pair<double, int>> weights() {
    return { { 0.5, 1 }, { 1.5, 2 } };
  }

  // Pairs spelled by the alias template, on their own and inside a list.
  couple<std::string, int> aliased_entry() {
    return { "two", 2 };
  }

  std::vector<couple<double, int>> aliased_weights() {
    return { { 2.5, 3 } };
  }

  // Sets are wrapped as an `Enumerable` with `#includes?`, `#<<` and `#delete`.
  std::set<int> evens(int count) {
    std::set<int> result;
    for (int i = 0; i < count; i++) result.insert(i * 2);
    return result;
  }

  int sumSet(const std::set<int> &values) {
    int sum = 0;
    for (int value : values) sum += value;
    return sum;
  }

  std::set<std::string> names() {
    return { "b", "a", "c" };
  }

  // Optionals are converted to and from a `T?`.
  std::optional<int> maybeInt(bool some) {
    if (some) return 42;
    return std::nullopt;
  }

  std::optional<std::string> maybeString(bool some) {
    if (some) return std::string("some");
    return std::nullopt;
  }

  std::optional<Point> maybePoint(bool some);

  int unwrapInt(const std::optional<int> &value) {
    return value.value_or(-1);
  }

  std::string greet(std::optional<std::string> name) {
    return "hello " + name.value_or("nobody");
  }

  std::vector<int> integers() {
    return std::vector<int>{ 1, 2, 3 };
  }

  std::vector<std::vector<int>> grid() {
    return { { 1, 4 }, { 9, 16 } };
  }

  std::vector<std::string> strings() {
    return std::vector<std::string>{ "One", "Two", "Three" };
  }

  bytearray chars() {
    return { 0x01, 0x04, 0x09 };
  }

  std::vector<rgb> palette() {
    return { 0xFF0000, 0x00FF00, 0x0000FF };
  }

  // Same container as `std::vector<rgb>`.
  std::vector<unsigned int> numbers() {
    return { 1u, 2u, 3u };
  }

  unsigned int brightest(const std::vector<rgb> &colors) {
    unsigned int max = 0;

    for (rgb c : colors) {
      if (c > max) max = c;
    }

    return max;
  }

  std::vector<std::vector<rgb>> palettes() {
    return { { 0xFF0000 }, { 0x00FF00, 0x0000FF } };
  }

  double sum(std::vector<double> list) {
    double d = 0;

    for (double c : list) {
      d += c;
    }

    return d;
  }

  std::vector<std::vector<double>> transpose(const std::vector<std::vector<double>> &mat) {
    std::size_t height = mat.size();
    std::size_t width = mat[0].size();

    std::vector<std::vector<double>> trsp;
    for (std::size_t x = 0; x < width; ++x) {
      std::vector<double> row;
      for (std::size_t y = 0; y < height; ++y) {
        row.push_back(mat[y][x]);
      }
      trsp.push_back(std::move(row));
    }

    return trsp;
  }

  std::map<int, std::string> numberNames() {
    return { { 1, "One" }, { 2, "Two" }, { 3, "Three" } };
  }

  std::unordered_map<std::string, int> wordLengths(const std::vector<std::string> &words) {
    std::unordered_map<std::string, int> lengths;

    for (const std::string &w : words) {
      lengths[w] = static_cast<int>(w.size());
    }

    return lengths;
  }

  int sumValues(const std::unordered_map<std::string, int> &map) {
    int sum = 0;

    for (const auto &pair : map) {
      sum += pair.second;
    }

    return sum;
  }

  phonebook phonebookEntries() {
    return { { "Alice", 123 }, { "Bob", 456 } };
  }

  std::map<int, std::vector<int>> multiples(int count) {
    std::map<int, std::vector<int>> result;

    for (int i = 1; i <= count; ++i) {
      result[i] = { i, i * 2, i * 3 };
    }

    return result;
  }

  int sumAll(const std::map<int, std::vector<int>> &map) {
    int sum = 0;

    for (const auto &pair : map) {
      for (int v : pair.second) {
        sum += v;
      }
    }

    return sum;
  }
};

class Point {
public:
  Point(int x, int y) : x(x), y(y) { }

  int getX() const { return x; }
  int getY() const { return y; }

  int x;
  int y;
};

// Point has no default constructor, so `std::map::operator[]` is unusable.
class Points {
public:
  std::map<std::string, Point> named() {
    return { { "origin", Point(0, 0) }, { "unit", Point(1, 1) } };
  }

  int sumX(const std::map<std::string, Point> &points) {
    int sum = 0;

    for (const auto &pair : points) {
      sum += pair.second.x;
    }

    return sum;
  }
};

// Mimics the API of Qt's `QMap`: Iterators have `key()` and `value()`,
// `insert()` replaces existing values, and `remove()` erases.
template <typename K, typename V>
class QtStyleMap {
  std::map<K, V> data;

public:
  typedef K key_type;
  typedef V mapped_type;

  class const_iterator {
    typename std::map<K, V>::const_iterator it;

  public:
    const_iterator(typename std::map<K, V>::const_iterator it) : it(it) { }

    const K &key() const { return it->first; }
    const V &value() const { return it->second; }
    const V &operator*() const { return it->second; }
    const_iterator &operator++() { ++it; return *this; }
    bool operator==(const const_iterator &other) const { return it == other.it; }
    bool operator!=(const const_iterator &other) const { return it != other.it; }
  };

  const_iterator begin() const { return data.begin(); }
  const_iterator end() const { return data.end(); }
  const_iterator find(const K &key) const { return data.find(key); }

  int size() const { return static_cast<int>(data.size()); }
  bool contains(const K &key) const { return data.count(key) > 0; }
  void insert(const K &key, const V &value) { data[key] = value; }
  int remove(const K &key) { return static_cast<int>(data.erase(key)); }
};

// Mimics the API of Qt's `QSet`: `contains()` tests, `remove()` erases.
template <typename T>
class QtStyleSet {
  std::set<T> data;

public:
  typedef T value_type;

  typename std::set<T>::const_iterator begin() const { return data.begin(); }
  typename std::set<T>::const_iterator end() const { return data.end(); }

  int size() const { return static_cast<int>(data.size()); }
  bool contains(const T &value) const { return data.count(value) > 0; }
  void insert(const T &value) { data.insert(value); }
  bool remove(const T &value) { return data.erase(value) > 0; }
};

class QtStyle {
public:
  QtStyleSet<int> primes() {
    QtStyleSet<int> set;
    set.insert(2);
    set.insert(3);
    set.insert(5);
    return set;
  }

  QtStyleMap<int, double> squareRoots() {
    QtStyleMap<int, double> map;
    map.insert(4, 2.0);
    map.insert(9, 3.0);
    return map;
  }
};

std::optional<Point> Containers::maybePoint(bool some) {
  if (some) return Point{ 3, 4 };
  return std::nullopt;
}
