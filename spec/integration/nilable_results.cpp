#include <vector>

// With `nilable_results: true`, a null pointer to a wrapped class is `nil`.
struct Node {
  Node *next = nullptr;
  int value = 0;

  Node *link() { return next; }
  Node &self() { return *this; }
  int valueOf(Node *node = nullptr) { return node ? node->value : -1; }

  static Node *none() { return nullptr; }
  static Node *some() { Node *n = new Node(); n->value = 5; return n; }
};

// A container element is never nil, nor a cast of self, nor the argument of a
// Crystal override.
struct Nodes {
  std::vector<Node *> all() {
    return { Node::some(), Node::some() };
  }
};

struct Left { int left() { return 1; } };
struct Right { int right() { return 2; } };
struct Both : Left, Right { };

struct Visitor {
  virtual ~Visitor() { }
  virtual int visit(Node *node) { return node->value; }
  int run() { return visit(Node::some()); }
};
