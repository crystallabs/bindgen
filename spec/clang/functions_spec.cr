require "./spec_helper"

describe "clang tool functions feature" do
  it "exports the C functions" do
    clang_tool(
      <<-CPP,
        void simple();
        void defaultArg(const char *thing = "Hello");
        int varArg(int count, ...);
        int arrayArg(int values[4]);
        extern "C" int externC();
        extern "C" { int externCContext(); }
        CPP
      "-f 'simple|.*Arg|externC.*'",
      functions: [
        {
          type:       "StaticMethod",
          name:       "simple",
          access:     "Public",
          isConst:    false,
          isVirtual:  false,
          isPure:     false,
          isExternC:  false,
          className:  "::",
          arguments:  [] of JSON::Any::Type,
          returnType: {isVoid: true},
        },
        {
          type:      "StaticMethod",
          name:      "defaultArg",
          access:    "Public",
          isConst:   false,
          isVirtual: false,
          isPure:    false,
          isExternC: false,
          className: "::",
          arguments: [
            {fullName: "const char *", hasDefault: true, value: "Hello"},
          ],
          returnType: {isVoid: true},
        },
        {
          type:      "StaticMethod",
          name:      "varArg",
          access:    "Public",
          isConst:   false,
          isVirtual: false,
          isPure:    false,
          isExternC: false,
          className: "::",
          arguments: [
            {fullName: "int", isVariadic: false},
            {fullName: "", isVariadic: true},
          ],
          returnType: {fullName: "int"},
        },
        { # Array parameters decay to pointers
          type:      "StaticMethod",
          name:      "arrayArg",
          arguments: [
            {fullName: "int *", pointer: 1, extents: [] of UInt64},
          ],
          returnType: {fullName: "int"},
        },
        {
          type:       "StaticMethod",
          name:       "externC",
          access:     "Public",
          isConst:    false,
          isVirtual:  false,
          isPure:     false,
          isExternC:  true,
          className:  "::",
          arguments:  [] of JSON::Any::Type,
          returnType: {fullName: "int"},
        },
        {
          type:       "StaticMethod",
          name:       "externCContext",
          access:     "Public",
          isConst:    false,
          isVirtual:  false,
          isPure:     false,
          isExternC:  true,
          className:  "::",
          arguments:  [] of JSON::Any::Type,
          returnType: {fullName: "int"},
        },
      ]
    )
  end

  it "omits tag keywords from type names" do
    clang_tool(
      <<-CPP,
        struct Plain { };
        union Both { int i; float f; };
        enum Kind { One };
        struct substruct { }; // Ends in a keyword
        template<typename T> struct Box { };

        struct Plain *tagged(struct Plain value, const union Both &both, enum Kind kind);
        substruct *tricky(Box<struct Plain> box, class Box<union Both *> *boxes);
        CPP
      "-f 'tagged|tricky'",
      functions: [
        {
          name:      "tagged",
          arguments: [
            {fullName: "Plain", baseName: "Plain"},
            {fullName: "const Both &", baseName: "Both"},
            {fullName: "Kind", baseName: "Kind"},
          ],
          returnType: {fullName: "Plain *", baseName: "Plain"},
        },
        {
          name:      "tricky",
          arguments: [
            {fullName: "Box<Plain>", baseName: "Box<Plain>"},
            {fullName: "Box<Both *> *", baseName: "Box<Both *>"},
          ],
          returnType: {fullName: "substruct *", baseName: "substruct"},
        },
      ],
    )
  end

  it "exports what it can from sources with errors" do
    clang_tool(
      <<-CPP,
        void before();
        void broken(UnknownType value);
        void after();
        CPP
      "-f 'before|after'",
      functions: [
        {name: "before"},
        {name: "after"},
      ],
    )
  end
end
