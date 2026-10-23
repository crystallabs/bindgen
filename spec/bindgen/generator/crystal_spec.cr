require "../../spec_helper"

private def add_class(parent, name, base_class = nil)
  origin = Bindgen::Parser::Class.new(name: name)
  klass = Bindgen::Graph::Class.new(origin: origin, name: name, parent: parent)
  klass.base_class = base_class
  klass
end

# Writes *root*, skipping the glue code in the first module.
private def generate(root)
  config = Bindgen::Configuration.from_yaml <<-YAML
    module: Test
    generators: { }
    parser: { files: [ "foo.h" ] }
    YAML
  db = Bindgen::TypeDatabase.new(config.types, config.cookbook)
  generator = Bindgen::Generator::Crystal.new(config, Bindgen::Configuration::Generator.dummy, db)

  io = IO::Memory.new
  generator.write_all(root, io)

  glue = "  " + Bindgen::GlueReader.read(cpp: false).gsub("\n", "\n  ") + "\n"
  io.to_s.sub(glue, "")
end

describe Bindgen::Generator::Crystal do
  describe "superclass order" do
    it "keeps the order if superclasses come first" do
      root = Bindgen::Graph::Namespace.new("Test")
      ns = Bindgen::Graph::Namespace.new("N", root)
      add_class(ns, "A")
      add_class(root, "B", "N::A")
      add_class(ns, "C")

      generate(root).should eq <<-CRYSTAL
        module Test
          module N
            @[BindgenWrapper]
            class A
            end
            @[BindgenWrapper]
            class C
            end
          end
          @[BindgenWrapper]
          class B < N::A
          end
        end

        CRYSTAL
    end

    it "moves a class after its superclass in the same container" do
      root = Bindgen::Graph::Namespace.new("Test")
      add_class(root, "B", "A")
      add_class(root, "C", "B")
      add_class(root, "A")
      add_class(root, "D")

      generate(root).should eq <<-CRYSTAL
        module Test
          @[BindgenWrapper]
          class A
          end
          @[BindgenWrapper]
          class B < A
          end
          @[BindgenWrapper]
          class C < B
          end
          @[BindgenWrapper]
          class D
          end
        end

        CRYSTAL
    end

    it "reopens modules and classes" do
      root = Bindgen::Graph::Namespace.new("Test")
      n = Bindgen::Graph::Namespace.new("N", root)
      add_class(n, "A")
      m = Bindgen::Graph::Namespace.new("M", n)
      add_class(m, "D", "C")
      add_class(n, "C", "B")
      outer = add_class(root, "Outer")
      add_class(outer, "Inner", "Later")
      add_class(root, "B", "N::A")
      add_class(root, "Later", "Outer")

      generate(root).should eq <<-CRYSTAL
        module Test
          module N
            @[BindgenWrapper]
            class A
            end
            module M
            end
          end
          @[BindgenWrapper]
          class Outer
          end
          @[BindgenWrapper]
          class B < N::A
          end
          module N
            @[BindgenWrapper]
            class C < B
            end
            module M
              @[BindgenWrapper]
              class D < C
              end
            end
          end
          @[BindgenWrapper]
          class Later < Outer
          end
          class Outer
            @[BindgenWrapper]
            class Inner < Later
            end
          end
        end

        CRYSTAL
    end
  end
end
