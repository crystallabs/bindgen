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

describe Bindgen::Parser::Method do
  describe "#out_arguments" do
    it "finds non-const references and pointers to converted types" do
      method = Parser.method("f", "Foo", Parser.void_type, [
        Parser.argument("a", "std::string &"),
        Parser.argument("b", "std::string *"),
        Parser.argument("c", "const std::string &"),
        Parser.argument("d", "std::string"),
      ])
      method.out_arguments(db).should eq([0, 1])
      method.filtered?(db).should be_false
    end

    it "counts built-in references and pointers next to a converted one" do
      method = Parser.method("f", "Foo", Parser.void_type, [
        Parser.argument("a", "int &"),
        Parser.argument("b", "bool *"),
        Parser.argument("c", "std::string &"),
        Parser.argument("d", "const int *"),
        Parser.argument("e", "int"),
      ])
      method.out_arguments(db).should eq([0, 1, 2])
    end

    it "doesn't count built-in references in a method without a converted one" do
      method = Parser.method("f", "Foo", Parser.void_type, [
        Parser.argument("a", "int &"),
        Parser.argument("b", "bool *"),
      ])
      method.out_arguments(db).should be_empty
      method.filtered?(db).should be_false
    end

    it "is empty for constructors, setters, signals and operators, which stay filtered" do
      args = [Parser.argument("a", "std::string &")]
      constructor = Parser.method("", "Foo", Parser.void_type, args, type: Bindgen::Parser::Method::Type::Constructor)
      constructor.out_arguments(db).should be_empty
      constructor.filtered?(db).should be_true

      signal = Parser.method("changed", "Foo", Parser.void_type, args, type: Bindgen::Parser::Method::Type::Signal)
      signal.out_arguments(db).should be_empty
      signal.filtered?(db).should be_true

      operator = Parser.method("operator>>", "Foo", Parser.void_type, args, type: Bindgen::Parser::Method::Type::Operator)
      operator.out_arguments(db).should be_empty
      operator.filtered?(db).should be_true

      setter = Parser.method("name", "Foo", Parser.void_type, [Parser.argument("a", "std::string *")], type: Bindgen::Parser::Method::Type::MemberSetter)
      setter.out_arguments(db).should be_empty
      setter.filtered?(db).should be_true
    end

    it "keeps filtering other indirections to converted types" do
      ["std::string **", "std::string *&", "std::string **&", "const std::string *"].each do |type|
        method = Parser.method("f", "Foo", Parser.void_type, [Parser.argument("a", type)])
        method.filtered?(db).should be_true
      end
    end
  end
end
