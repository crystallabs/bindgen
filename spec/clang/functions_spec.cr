require "./spec_helper"

describe "clang tool functions feature" do
  it "exports the C functions" do
    clang_tool(
      %[
        void simple();
        void defaultArg(const char *thing = "Hello");
        int varArg(int count, ...);
        extern "C" int externC();
        extern "C" { int externCContext(); }
      ],
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
end
