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
