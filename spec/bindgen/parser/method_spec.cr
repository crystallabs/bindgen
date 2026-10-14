require "../../spec_helper"

private def db
  Bindgen::TypeDatabase.new(Bindgen::TypeDatabase::Configuration.new, "boehmgc-cpp")
end

# `Parser::Type.parse` doesn't know built-in types.
private def int_array
  Bindgen::Parser::Type.new(
    base_name: "int", full_name: "int [4]", const: false, reference: false,
    pointer: 1, builtin: true, extents: [4_u64],
  )
end

describe Bindgen::Parser::Method do
  describe "#filtered?" do
    it "filters methods returning a C array" do
      method = Parser.method("get", "Foo", Parser.type("int [4]"))
      method.filtered?(db).should be_true
    end

    it "filters methods taking a C array" do
      method = Parser.method("set", "Foo", Parser.void_type, [Parser.argument("values", "int [4]")])
      method.filtered?(db).should be_true
    end

    it "keeps getters of C array members" do
      getter = Parser.method("v", "Foo", int_array, type: Bindgen::Parser::Method::Type::MemberGetter)
      getter.filtered?(db).should be_false

      getter = Parser.method("v", "Foo", int_array, type: Bindgen::Parser::Method::Type::StaticGetter)
      getter.filtered?(db).should be_false
    end

    it "filters getters of C arrays of unknown types" do
      getter = Parser.method("v", "Foo", Parser.type("Unknown [4]"), type: Bindgen::Parser::Method::Type::MemberGetter)
      getter.filtered?(db).should be_true
    end
  end
end
