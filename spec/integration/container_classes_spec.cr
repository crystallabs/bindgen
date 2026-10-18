require "./spec_helper"

describe "container classes feature" do
  it "works" do
    build_and_run("container_classes") do
      context "container instantiation listed in classes" do
        it "is wrapped under the configured name" do
          Test::List.of(String).should eq(Test::StringList)
          list = Test::StringList.from(["b", "a"])
          list.should be_a(Test::List(String))
          list.size.should eq(2)
          list.to_a.should eq(["b", "a"])
        end

        it "has the parsed methods" do
          list = Test::StringList.from(["b", "a"])
          list.first.should eq("b")
          list.take_last.should eq("a")              # Declared through a class-local typedef
          list.responds_to?(:cursor).should be_false # Returns a nested type
          list.clear
          list.size.should eq(0)
        end

        it "has the methods of the wrapped specialization" do
          list = Test::StringList.from(["b", "ccc", "a"])
          list.should be_a(Test::StringListMethods)
          list.longest.should eq("ccc")
        end

        it "keeps the container conversions" do
          Test::Lists.new.names.to_a.should eq(["Alice", "Bob"])
          Test::Lists.new.joined(["x", "y"]).should eq("x+y")
          Test::Lists.new.joined(Test::Lists.new.names).should eq("Alice+Bob")
          Test::Lists.new.halves.to_a.should eq([0.5, 1.5])
          Test::Lists.new.doubles.to_a.should eq([2.5, 3.5]) # Through a typedef
          Test::Lists.new.total_of([1.5, 2.0]).should eq(3.5)
        end

        it "is written after the types it names" do
          Test::Lists.new.colors.to_a.should eq([Test::Color::Red, Test::Color::Blue])
        end
      end

      context "class deriving from a container instantiation" do
        it "is an Indexable" do
          polygon = Test::Polygon.new
          polygon.should be_a(Test::List(Int32))
          polygon << 1 << 2 << 3
          polygon.to_a.should eq([1, 2, 3])
          polygon.perimeter.should eq(6)
        end

        it "is passed and returned like the container" do
          Test::Lists.new.total(Test::Polygon.new([2, 3])).should eq(5)
          Test::Lists.new.perimeter(Test::Polygon.new([2, 3])).should eq(5)
          Test::Lists.new.triangle.to_a.should eq([3, 4, 5])
          Test::Lists.new.triangle.perimeter.should eq(12)
        end
      end
    end
  end
end
