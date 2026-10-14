struct Item {
  int value;
};

class Arrays {
public:
  int values[4] = { 1, 2, 3, 4 };
  float matrix[2][3] = { { 1, 2, 3 }, { 4, 5, 6 } };

  // Decays to `const int *`.
  int first(const int list[4]) { return list[0]; }

  int sum(const int (&list)[4]) {
    return list[0] + list[1] + list[2] + list[3];
  }

  void fill(int (&list)[4], int value) {
    for (int &v : list) v = value;
  }

  float trace(const float (&m)[3][3]) {
    return m[0][0] + m[1][1] + m[2][2];
  }

  int (&valuesRef())[4] { return values; }
  const float (&matrixRef() const)[2][3] { return matrix; }

  static int (&staticRef())[2] {
    static int data[2] = { 7, 8 };
    return data;
  }

  // Filtered: Unknown bounds, wrapped elements, overridable.
  void unknownBound(int (&list)[]) { }
  void items(Item (&list)[2]) { }
  virtual void overridable(int (&list)[4]) { }
  virtual int answer() { return 42; }
};

int arraySum(const short (&list)[3]) {
  return list[0] + list[1] + list[2];
}
