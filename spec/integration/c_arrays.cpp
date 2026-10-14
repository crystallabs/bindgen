struct Item {
  int value;
};

// Copied into a `lib struct`.
struct Grid {
  int (*rows)[3];
  int count;
};

class Arrays {
public:
  int values[4] = { 1, 2, 3, 4 };
  float matrix[2][3] = { { 1, 2, 3 }, { 4, 5, 6 } };
  int (*current)[4] = &values;

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

  int (*valuesPtr())[4] { return &values; }

  int sumRows(const int (*rows)[3], int count) {
    int sum = 0;
    for (int i = 0; i < count; i++) sum += rows[i][0] + rows[i][1] + rows[i][2];
    return sum;
  }

  bool isNull(const int (*rows)[3] = nullptr) { return !rows; }

  // Decays to `int (*)[3]`.
  int corner(int m[][3]) { return m[1][2]; }

  int gridSum(Grid grid) { return sumRows(grid.rows, grid.count); }

  static int (&staticRef())[2] {
    static int data[2] = { 7, 8 };
    return data;
  }

  // Filtered: Unknown bounds, wrapped elements, overridable.
  void unknownBound(int (&list)[]) { }
  void unknownBoundPtr(int (*list)[]) { }
  void items(Item (&list)[2]) { }
  void itemsPtr(Item (*list)[2]) { }
  void nested(int (*(*list)[2])[3]) { }
  virtual void overridable(int (&list)[4]) { }
  virtual int answer() { return 42; }
};

int arraySum(const short (&list)[3]) {
  return list[0] + list[1] + list[2];
}
