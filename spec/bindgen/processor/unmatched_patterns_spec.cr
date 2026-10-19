require "../../spec_helper"

private def rules(yaml)
  Bindgen::TypeDatabase::Configuration.from_yaml(yaml)["Widget"]
    .as(Bindgen::TypeDatabase::TypeConfig)
end

describe Bindgen::Processor::Base do
  config = Bindgen::Configuration.from_yaml <<-YAML
    module: Foo
    generators: { }
    parser: { files: [ "foo.h" ] }
    YAML
  db = Bindgen::TypeDatabase.new(Bindgen::TypeDatabase::Configuration.new, "boehmgc-cpp")
  processor = Bindgen::Processor::CppWrapper.new(config, db)

  # A Widget with a constructor, `addWidget`, and `setFilter` for the Crystal
  # platform only, binding `installEventFilter` of its superclass Object.
  klass = Bindgen::Graph::Class.new(Bindgen::Parser::Class.new(name: "Widget"), "Widget")
  widget_type = Parser.type("Widget *")
  {"", "addWidget"}.each do |name|
    origin = Parser.method(name, "Widget", widget_type, [Parser.argument("w", "Widget *")])
    Bindgen::Graph::Method.new(origin, name, klass)
  end
  specific = klass.platform_specific(Bindgen::Graph::Platform::Crystal)
  origin = Parser.method("setFilter", "Widget", widget_type, [Parser.argument("w", "Widget *")])
  Bindgen::Graph::Method.new(origin, "setFilter", specific)
  origin = Parser.method("installEventFilter", "Object", widget_type, [Parser.argument("w", "Widget *")])
  Bindgen::Graph::Method.new(origin, "installEventFilter", klass)

  describe "#unmatched_patterns" do
    it "is empty for patterns matching a method" do
      widget = rules(<<-YAML)
        Widget:
          keep_alive: { ^addWidget$: true, ^set: [0] }
          depends_on: [^$]
        YAML

      processor.unmatched_patterns(klass, widget.keep_alive).should be_empty
      processor.unmatched_patterns(klass, widget.depends_on).should be_empty
    end

    it "is empty without rules" do
      processor.unmatched_patterns(klass, Bindgen::TypeDatabase::KeepAlive.new).should be_empty
    end

    it "returns the patterns matching no method" do
      widget = rules(<<-YAML)
        Widget:
          keep_alive: [^addWidget$, ^addWidgte$, ^installEventFilter$]
          depends_on: [^$, ^Widget$]
        YAML

      processor.unmatched_patterns(klass, widget.keep_alive).should eq [/^addWidgte$/, /^installEventFilter$/]
      processor.unmatched_patterns(klass, widget.depends_on).should eq [/^Widget$/]
    end
  end
end
