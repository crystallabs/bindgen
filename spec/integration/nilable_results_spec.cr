require "./spec_helper"

describe "nilable_results feature" do
  it "works" do
    build_and_run("nilable_results") do
      # The argument of an override is the class itself, not nilable.
      class Doubling < Test::Visitor
        def visit(node : Test::Node) : Int32
          node.value * 2
        end
      end

      # An override returning the nilable result type
      class NilFinder < Test::Finder
        def find : Test::Node?
          nil
        end
      end

      it "passes a nil result of an override to C++ as null" do
        Test::Finder.new.found.should be_true
        NilFinder.new.found.should be_false
      end

      it "returns nil for a null pointer" do
        Test::Node.none.should be_nil
        Test::Node.new.link.should be_nil
        typeof(Test::Node.new.link).should eq(Test::Node?)
      end

      it "returns the wrapper for a pointer" do
        some = Test::Node.some
        some.should be_a(Test::Node)
        some.try(&.value).should eq(5)
        Test::Node.new.self.should be_a(Test::Node) # A reference, never nil
      end

      it "keeps container elements, casts and override arguments non-nil" do
        nodes = Test::Nodes.new.all
        typeof(nodes.first).should eq(Test::Node)
        nodes.map(&.value).should eq([5, 5])
        Test::Nodes.new.grid.map(&.map(&.value)).should eq([[5, 5], [5]])
        typeof(Test::Both.new.as_right).should eq(Test::Right)
        Test::Both.new.as_right.right.should eq(2)
        Test::Visitor.new.run.should eq(5)
        Doubling.new.run.should eq(10)
      end

      it "keeps nilable arguments" do
        Test::Node.new.value_of(nil).should eq(-1)
        Test::Node.new.value_of(Test::Node.some.as(Test::Node)).should eq(5)
      end

      it "takes a nilable variable as argument" do
        maybe = Test::Node.some.as(Test::Node?) # A union, not nil nor the class
        Test::Node.new.value_of(maybe).should eq(5)
        Test::Node.new.value_of(nil.as(Test::Node?)).should eq(-1)
      end
    end
  end
end
