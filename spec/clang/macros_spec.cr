require "./spec_helper"

describe "clang tool macros feature" do
  it "exports the macros" do
    clang_tool(
      %[
        #define THING_ONE 1
        #define THING_TWO 2
        #define ANOTHER 3
        #define NOT_EXPORTED 4
        #define ADD_ONE(x) (x + 1)
        #define ADD_ALL(first, ...) add(first, __VA_ARGS__)
        #define ADD_GNU(first, rest...) add(first, rest)

        #define EVALUATE_INT32 1
        #define EVALUATE_INT64 1LL
        #define EVALUATE_UINT64 1LLU
        #define EVALUATE_UINT32 1U
        #define EVALUATE_NEGATIVE_INT32 -123
        #define EVALUATE_NEGATIVE_INT64 -123LL
        #define EVALUATE_LARGE_UINT64 9223372036854775808
        #define EVALUATE_LARGE_INT64 9223372036854775807
        #define EVALUATE_TRUE true
        #define EVALUATE_FALSE false
        #define EVALUATE_FLOAT 3.5
      ],
      "-m 'THING_.*|ANOTHER|ADD_.*|EVALUATE_.*'",
      macros: [
        {
          name:       "THING_ONE",
          isFunction: false,
          isVarArg:   false,
          arguments:  [] of String,
          value:      "1",
        },
        {
          name:       "THING_TWO",
          isFunction: false,
          isVarArg:   false,
          arguments:  [] of String,
          value:      "2",
        },
        {
          name:       "ANOTHER",
          isFunction: false,
          isVarArg:   false,
          arguments:  [] of String,
          value:      "3",
        },
        {
          name:       "ADD_ONE",
          isFunction: true,
          isVarArg:   false,
          arguments:  ["x"],
          value:      "(x + 1)",
        },
        {
          name:       "ADD_ALL",
          isFunction: true,
          isVarArg:   true,
          arguments:  ["first"],
          value:      "add(first, __VA_ARGS__)",
        },
        {
          name:       "ADD_GNU",
          isFunction: true,
          isVarArg:   true,
          arguments:  ["first", "rest"],
          value:      "add(first, rest)",
        },
        {
          name:       "EVALUATE_INT32",
          isFunction: false,
          value:      "1",
          type:       {fullName: "int"},
          evaluated:  1i32,
        },
        {
          name:       "EVALUATE_INT64",
          isFunction: false,
          value:      "1LL",
          type:       {fullName: "long long"},
          evaluated:  1i64,
        },
        {
          name:       "EVALUATE_UINT64",
          isFunction: false,
          value:      "1LLU",
          type:       {fullName: "unsigned long long"},
          evaluated:  1u64,
        },
        {
          name:       "EVALUATE_UINT32",
          isFunction: false,
          value:      "1U",
          type:       {fullName: "unsigned int"},
          evaluated:  1u32,
        },
        {
          name:       "EVALUATE_NEGATIVE_INT32",
          isFunction: false,
          value:      "-123",
          type:       {fullName: "int"},
          evaluated:  -123i32,
        },
        {
          name:       "EVALUATE_NEGATIVE_INT64",
          isFunction: false,
          value:      "-123LL",
          type:       {fullName: "long long"},
          evaluated:  -123i64,
        },
        {
          name:       "EVALUATE_LARGE_UINT64",
          isFunction: false,
          value:      "9223372036854775808",
          type:       {fullName: "unsigned long long"},
          evaluated:  9223372036854775808_u64,
        },
        { # It detects "unsigned long long" above, but just "long" here.
          name:       "EVALUATE_LARGE_INT64",
          isFunction: false,
          value:      "9223372036854775807",
          type:       {fullName: "long"},
          evaluated:  9223372036854775807i64,
        },
        {
          name:       "EVALUATE_TRUE",
          isFunction: false,
          value:      "true",
          type:       {fullName: "bool"},
          evaluated:  true,
        },
        {
          name:       "EVALUATE_FALSE",
          isFunction: false,
          value:      "false",
          type:       {fullName: "bool"},
          evaluated:  false,
        },
        {
          name:       "EVALUATE_FLOAT",
          isFunction: false,
          value:      "3.5",
          type:       {fullName: "double"},
          evaluated:  3.5,
        },
      ]
    )
  end
end
