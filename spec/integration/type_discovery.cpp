#include <string>

/* Type discovery, SPEC.md §2.3.7: a pointer or reference to a polymorphic
 * class is wrapped in the class of the object's dynamic type. */

struct Shape {
  virtual ~Shape() { }
  virtual std::string name() const { return "shape"; }
  int sides = 0;
};

struct Polygon : Shape {
  std::string name() const override { return "polygon"; }
  int corners() const { return sides; }
};

struct Triangle : Polygon {
  Triangle() { sides = 3; }
  std::string name() const override { return "triangle"; }
  int area() const { return 6; }
};

// Not wrapped: discovered as the nearest wrapped class, Polygon.
struct Rectangle : Polygon {
  Rectangle() { sides = 4; }
  std::string name() const override { return "rectangle"; }
};

// Abstract, discovered through its `Impl` class.
struct Round : Shape {
  virtual double radius() const = 0;
};

struct Circle : Round {
  std::string name() const override { return "circle"; }
  double radius() const override { return 1.5; }
};

// A second base: not a Crystal superclass, so nothing is discovered through it.
struct Named {
  virtual ~Named() { }
  virtual std::string label() const { return "named"; }
};

struct Labelled : Shape, Named {
  std::string label() const override { return "labelled"; }
};

struct Point {
  int x = 1;
};

struct Point3 : Point {
  int z = 2;
};

struct Shapes {
  Shape *triangle() { return &tri; }
  Shape *rectangle() { return &rect; }
  Shape *circle() { return &circ; }
  Shape *shape() { return &plain; }
  Shape *none() { return nullptr; }
  Shape &triangleRef() { return tri; }
  Shape triangleValue() { return tri; }
  Round *round() { return &circ; }
  Named *named() { return &lab; }
  Shape *labelled() { return &lab; }
  Point *point3() { return &p3; }

  // A pointer or reference argument of a callback is discovered too.
  virtual std::string visit(Shape *shape) { return shape->name(); }
  virtual std::string visitRef(const Shape &shape) { return shape.name(); }
  std::string visitTriangle() { return visit(&tri); }
  std::string visitCircleRef() { return visitRef(circ); }

  void keep(Shape *shape) { kept = shape; }
  Shape *last() { return kept; }

  Triangle tri;
  Rectangle rect;
  Circle circ;
  Shape plain;
  Labelled lab;
  Point3 p3;
  Shape *kept = nullptr;
};
