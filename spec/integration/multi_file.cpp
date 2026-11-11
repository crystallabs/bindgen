#include <string>
#include <vector>

class Shape {
public:
  virtual ~Shape() { }
  virtual int sides() const { return 0; }
  int doubledSides() const { return sides() * 2; }
};

class Canvas {
public:
  std::vector<int> sizes(int count) const {
    std::vector<int> result;
    for (int i = 1; i <= count; i++) result.push_back(i * 10);
    return result;
  }

  int measure(const Shape &shape) const { return shape.sides(); }

  struct Brush {
    int width() const { return 3; }
  };
};

inline int multi_add(int a, int b) { return a + b; }
