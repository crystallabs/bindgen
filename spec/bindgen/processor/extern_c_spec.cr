require "../../spec_helper"

private def argument(name, type)
  Bindgen::Parser::Argument.new(name, Bindgen::Parser::Type.parse(type))
end

describe Bindgen::Processor::ExternC do
  config = Bindgen::Configuration.from_yaml <<-YAML
  module: Foo
  generators: { }
  parser: { files: [ "foo.h" ] }
  YAML

  doc = Bindgen::Parser::Document.new
  db = Bindgen::TypeDatabase.new(Bindgen::TypeDatabase::Configuration.new, "boehmgc-cpp")
  db.add("HasToCpp", to_cpp: Bindgen::Template.from_string("TO_CPP"), copy_structure: true)
  db.add("HasFromCpp", from_cpp: Bindgen::Template.from_string("FROM_CPP"), copy_structure: true)
  db.add("PassByValue", pass_by: Bindgen::TypeDatabase::PassBy::Reference)

  extern_c_void_func = Bindgen::Parser::Method.new(
    name: "foo",
    className: "",
    arguments: [] of Bindgen::Parser::Argument,
    returnType: Bindgen::Parser::Type::VOID,
    isExternC: true,
  )

  void_result = Bindgen::Cpp::Pass.new(db).to_cpp(Bindgen::Parser::Type::VOID)

  dummy_call = Bindgen::Call.new(
    name: "foo",
    result: void_result,
    arguments: [] of Bindgen::Call::Argument,
    body: Bindgen::Call::EmptyBody.new,
    origin: extern_c_void_func,
  )

  subject = Bindgen::Processor::ExternC.new(config, db)

  it "requires the method to use the C ABI" do
    graph = Bindgen::Graph::Namespace.new("ROOT")
    method = Bindgen::Graph::Method.new(
      name: "foo",
      parent: graph,
      origin: Bindgen::Parser::Method.new(
        name: "foo",
        className: "",
        arguments: [] of Bindgen::Parser::Argument,
        returnType: Bindgen::Parser::Type::VOID,
        isExternC: false,
      )
    )

    subject.process(graph, doc)

    method.tag?(Bindgen::Graph::Method::EXPLICIT_BIND_TAG).should be_nil
  end

  it "requires the method to have no to_cpp arguments (explicit)" do
    graph = Bindgen::Graph::Namespace.new("ROOT")
    method = Bindgen::Graph::Method.new(
      name: "foo",
      parent: graph,
      origin: Bindgen::Parser::Method.new(
        name: "foo",
        className: "",
        arguments: [
          argument("a", "int"),
          argument("b", "const char *"),
          argument("c", "HasToCpp"),
        ],
        returnType: Bindgen::Parser::Type::VOID,
        isExternC: true,
      )
    )

    subject.process(graph, doc)
    method.tag?(Bindgen::Graph::Method::EXPLICIT_BIND_TAG).should be_nil
  end

  it "requires the method to have no to_cpp arguments (implicit)" do
    graph = Bindgen::Graph::Namespace.new("ROOT")
    method = Bindgen::Graph::Method.new(
      name: "foo",
      parent: graph,
      origin: Bindgen::Parser::Method.new(
        name: "foo",
        className: "",
        arguments: [
          argument("a", "int"),
          argument("b", "const char *"),
          argument("c", "PassByValue *"),
        ],
        returnType: Bindgen::Parser::Type::VOID,
        isExternC: true,
      )
    )

    subject.process(graph, doc)
    method.tag?(Bindgen::Graph::Method::EXPLICIT_BIND_TAG).should be_nil
  end

  it "requires the methods return type to have no from_cpp (explicit)" do
    graph = Bindgen::Graph::Namespace.new("ROOT")
    method = Bindgen::Graph::Method.new(
      name: "foo",
      parent: graph,
      origin: Bindgen::Parser::Method.new(
        name: "foo",
        className: "",
        arguments: [
          argument("a", "int"),
          argument("b", "const char *"),
        ],
        returnType: Bindgen::Parser::Type.parse("HasFromCpp"),
        isExternC: true,
      )
    )

    subject.process(graph, doc)
    method.tag?(Bindgen::Graph::Method::EXPLICIT_BIND_TAG).should be_nil
  end

  it "requires the methods return type to have no from_cpp (implicit)" do
    graph = Bindgen::Graph::Namespace.new("ROOT")
    method = Bindgen::Graph::Method.new(
      name: "foo",
      parent: graph,
      origin: Bindgen::Parser::Method.new(
        name: "foo",
        className: "",
        arguments: [
          argument("a", "int"),
          argument("b", "const char *"),
        ],
        returnType: Bindgen::Parser::Type.parse("PassByValue *"),
        isExternC: true,
      )
    )

    subject.process(graph, doc)
    method.tag?(Bindgen::Graph::Method::EXPLICIT_BIND_TAG).should be_nil
  end

  it "skips methods having a CrystalBinding call" do
    graph = Bindgen::Graph::Namespace.new("ROOT")
    method = Bindgen::Graph::Method.new(
      name: "foo",
      parent: graph,
      origin: extern_c_void_func,
    )

    method.calls[Bindgen::Graph::Platform::CrystalBinding] = dummy_call

    subject.process(graph, doc)
    method.tag?(Bindgen::Graph::Method::EXPLICIT_BIND_TAG).should be_nil
  end

  it "skips methods having a Cpp call" do
    graph = Bindgen::Graph::Namespace.new("ROOT")
    method = Bindgen::Graph::Method.new(
      name: "foo",
      parent: graph,
      origin: extern_c_void_func,
    )

    method.calls[Bindgen::Graph::Platform::Cpp] = dummy_call

    subject.process(graph, doc)
    method.tag?(Bindgen::Graph::Method::EXPLICIT_BIND_TAG).should be_nil
  end

  it "skips methods having EXPLICIT_BIND_TAG set" do
    graph = Bindgen::Graph::Namespace.new("ROOT")
    method = Bindgen::Graph::Method.new(
      name: "foo",
      parent: graph,
      origin: extern_c_void_func,
    )

    method.set_tag(Bindgen::Graph::Method::EXPLICIT_BIND_TAG, "unit-test")
    subject.process(graph, doc)
    method.tag?(Bindgen::Graph::Method::EXPLICIT_BIND_TAG).should eq("unit-test")
  end

  it "adds the EXPLICIT_BIND_TAG otherwise" do
    graph = Bindgen::Graph::Namespace.new("ROOT")
    method = Bindgen::Graph::Method.new(
      name: "foo",
      parent: graph,
      origin: Bindgen::Parser::Method.new(
        name: "libfoo_bar",
        className: "",
        arguments: [
          argument("a", "int"),
          argument("b", "const char *"),
          argument("c", "HasFromCpp"),
        ],
        returnType: Bindgen::Parser::Type.parse("HasToCpp"),
        isExternC: true,
      )
    )

    subject.process(graph, doc)
    method.tag?(Bindgen::Graph::Method::EXPLICIT_BIND_TAG).should eq("libfoo_bar")
  end
end
