require "./spec_helper"

describe "clang tool classes feature" do
  it "exports the width of bit-fields" do
    clang_tool(
      %[
        struct Flags {
          unsigned plain;
          unsigned narrow : 3;
          int wide : 12;
        };
      ],
      "-c Flags",
      classes: {
        Flags: {
          fields: [
            {name: "plain", bitField: nil},
            {name: "narrow", bitField: 3},
            {name: "wide", bitField: 12},
          ],
        },
      },
    )
  end

  it "exports if a constructor is declared" do
    clang_tool(
      %[
        struct Plain { int x; };
        struct Defaulted { Defaulted() = default; int x; };
        struct Deleted { Deleted(int) = delete; int x; };
        struct Provided { Provided() { } int x; };

        // Declares the implicit constructors of `Plain`.
        Plain copy(Plain plain = Plain()) { return plain; }
      ],
      "-c Plain -c Defaulted -c Deleted -c Provided",
      classes: {
        Plain:     {hasUserDeclaredConstructor: false},
        Defaulted: {hasUserDeclaredConstructor: true},
        Deleted:   {hasUserDeclaredConstructor: true},
        Provided:  {hasUserDeclaredConstructor: true},
      },
    )
  end

  it "tells pointers to arrays and arrays of pointers apart" do
    clang_tool(
      %[
        struct Arrays {
          int *pointers[4];
          int (*array)[4];
          const int (&ref)[2][3];
        };
      ],
      "-c Arrays",
      classes: {
        Arrays: {
          fields: [
            {name: "pointers", baseName: "int", pointer: 2, extents: [4]},
            {name: "array", baseName: "int[4]", pointer: 1, extents: [] of UInt64},
            {name: "ref", baseName: "const int[2][3]", pointer: 1, isReference: true},
          ],
        },
      },
    )
  end

  it "ignores a class template of the same name in another scope" do
    clang_tool(
      %[
        namespace detail { template<typename T> struct Node { T *next; }; }
        struct Node { int value; };
      ],
      "-c Node",
      classes: {
        Node: {fields: [{name: "value"}]},
      },
    )
  end

  it "exports if a class is final" do
    clang_tool(
      %[
        struct Open { virtual int f(); };
        struct Closed final { virtual int f(); };
      ],
      "-c Open -c Closed",
      classes: {
        Open:   {isFinal: false},
        Closed: {isFinal: true},
      },
    )
  end

  it "exports if a class is trivially copyable and standard-layout" do
    clang_tool(
      %[
        struct Plain { int x; };
        struct Copying { Copying(const Copying &) { } int x; };
        struct Mixed { int x; private: int y; };
        struct Derived : Plain { int y; };
      ],
      "-c Plain -c Copying -c Mixed -c Derived",
      classes: {
        Plain:   {isTriviallyCopyable: true, isStandardLayout: true},
        Copying: {isTriviallyCopyable: false, isStandardLayout: true},
        Mixed:   {isTriviallyCopyable: true, isStandardLayout: false},
        Derived: {isTriviallyCopyable: true, isStandardLayout: false},
      },
    )
  end

  it "rejects class templates" do
    file = File.tempfile("bindgen-clang-test")
    file.puts("template<typename T> class Templated { T *ptr; };")
    file.flush

    tool = ENV["BINDGEN_BIN"]? || Bindgen::Parser::Runner::BINARY_PATH
    error = IO::Memory.new
    status = Process.run(tool, [file.path, "-c", "Templated", "--", "-x", "c++"], error: error)

    status.normal_exit?.should be_true
    status.success?.should be_false
    error.to_s.should contain("'Templated' is a class template")
  ensure
    file.try(&.delete)
  end
end
