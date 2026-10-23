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

  // `nilable: { tail: false }`: known to be non-null.
  Node *tail() { return next ? next : this; }
  // `nilable: { valueOrDefault: [0] }`: accepts null without a default.
  int valueOrDefault(Node *node) { return node ? node->value : -1; }
  // `rename: { weight: heaviness }`
  int weight() { return value * 2; }
};

// A container element is never nil, nor a cast of self, nor the argument of a
// Crystal override.
struct Nodes {
  std::vector<Node *> all() {
    return { Node::some(), Node::some() };
  }

  // Only the outer vector is listed in the configuration.
  std::vector<std::vector<Node *>> grid() {
    return { all(), { Node::some() } };
  }
};

struct Left { int left() { return 1; } };
struct Right { int right() { return 2; } };
struct Both : Left, Right { };

struct Visitor {
  virtual ~Visitor() { }
  virtual int visit(Node *node) { return node->value; }
  int run() { return visit(Node::some()); }

  // Renamed to `score`: a Crystal subclass overrides it under that name.
  virtual int rate(Node *node) { return node->value; }
  int runRate() { return rate(Node::some()); }
};

// `nilable: { find: true }` without `nilable_results` applies to a subclass
// too; the override returns `Node?`.
struct Seeker {
  virtual ~Seeker() { }
  virtual Node *seek() { return nullptr; }
  bool sought() { return seek() != nullptr; }
};

// An override may return nil for a pointer, which reaches C++ as null.
struct Finder {
  virtual ~Finder() { }
  virtual Node *find() { return Node::some(); }
  bool found() { return find() != nullptr; }
};
