#include <functional>
#include <string>

/* `std::function` arguments, SPEC.md §2.2.6: taken as a block or `Proc`. */

struct Button {
  // Stored by C++: the Crystal closure stays alive as long as the function.
  void onClick(std::function<void()> f) { clicked = f; }
  bool trigger() {
    if (!clicked) return false;
    clicked();
    return true;
  }
  void release() { clicked = nullptr; }

  // Called right away, with converted arguments and result.
  int each(int count, std::function<int(int, const std::string &)> f) {
    int sum = 0;
    for (int i = 0; i < count; i++) sum += f(i, "item");
    return sum;
  }

  std::string transform(std::function<std::string(const std::string &)> f, const std::string &s) {
    return f(s);
  }

  // Not the last argument, and by const reference: a `Proc` argument.
  void setFilter(const std::function<bool(int)> &f, int threshold) {
    filter = f;
    this->threshold = threshold;
  }
  bool passes(int value) { return filter && value > threshold && filter(value); }

  // Virtual: called through the wrapper, not overridable from Crystal.
  virtual int visit(std::function<int(int)> f) { return f(21); }

  // Not supported: a `std::function` result, and a bare function pointer.
  std::function<void()> handler() const { return clicked; }
  void raw(void (*cb)(int)) { cb(1); }

  std::function<void()> clicked;
  std::function<bool(int)> filter;
  int threshold = 0;
};
