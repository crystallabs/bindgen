require "./spec_helper"

describe "class template instantiations" do
  it "works" do
    build_and_run("templates") do
      context "instantiation with a type template argument" do
        it "wraps the constructor and methods" do
          box = Test::IntBox.new(5)
          box.get.should eq(5)
          box.set(7)
          box.get.should eq(7)
        end

        it "wraps fields" do
          box = Test::IntBox.new(5)
          box.value.should eq(5)
          box.value = 8
          box.get.should eq(8)
        end

        it "wraps static methods" do
          Test::IntBox.count.should eq(4)
        end

        it "wraps free operators" do
          (Test::IntBox.new(1) == Test::IntBox.new(1)).should be_true
          (Test::IntBox.new(1) == Test::IntBox.new(2)).should be_false
        end

        it "substitutes wrapped classes" do
          box = Test::PointBox.new(Test::Point.new(1, 2))
          box.get.x.should eq(1)
          box.set(Test::Point.new(3, 4))
          box.value.y.should eq(4)
          Test::PointBox.count.should eq(8)
        end

        it "wraps nested instantiations" do
          box = Test::BoxFactory.new.nested(6)
          box.should be_a(Test::NestedBox)
          box.get.should be_a(Test::IntBox)
          box.get.get.should eq(6)
        end
      end

      context "instantiation with non-type template arguments" do
        it "wraps the class" do
          array = Test::IntArray3.new
          array.size.should eq(3)
          array.set(1, 5)
          array.at(1).should eq(5)
          array.sum.should eq(5)
        end

        it "supports negative and boolean values" do
          Test::Offset::MinusTwice.new.apply(10).should eq(6)
        end
      end

      context "instantiation with a default template argument" do
        it "wraps the class" do
          scaled = Test::ScaledInt.new
          scaled.base = 4
          scaled.factor.should eq(2.0)
          scaled.scaled.should eq(8)
        end
      end

      context "methods using instantiations" do
        it "returns by value" do
          Test::BoxFactory.new.make(3).get.should eq(3)
          Test::BoxFactory.new.triple.sum.should eq(6)
          Test::BoxFactory.new.scaled(5).scaled.should eq(10)
          Test::BoxFactory.new.offset.apply(0).should eq(-4)
        end

        it "returns by pointer" do
          Test::BoxFactory.new.make_pointer(4).get.should eq(4)
        end

        it "returns through a typedef" do
          Test::BoxFactory.new.make_typedef(9).should be_a(Test::IntBox)
          Test::BoxFactory.new.make_typedef(9).get.should eq(9)
        end

        it "takes arguments" do
          factory = Test::BoxFactory.new
          factory.unbox(Test::IntBox.new(2)).should eq(2)
          factory.unbox_pointer(Test::IntBox.new(3)).should eq(3)
          factory.unbox_point(Test::PointBox.new(Test::Point.new(1, 2))).should eq(3)
        end

        it "skips methods using unconfigured instantiations" do
          {{ Test::BoxFactory.methods.map(&.name.stringify) }}.should_not contain("unknown")
        end
      end

      context "typedef of an instantiation" do
        it "is wrapped under the typedef's name" do
          pair = Test::Reader.new.pair
          pair.should be_a(Test::FloatPair)
          pair.size.should eq(2)
          pair.at(1).should eq(2.5_f32)
          Test::Reader.new.spelled_out.should be_a(Test::FloatPair)
          (pair == Test::Reader.new.spelled_out).should be_true
        end
      end

      context "member class template" do
        it "wraps an instantiation" do
          result = Test::Reader.new.read
          result.should be_a(Test::IntResult)
          result.data.should eq(7)
          result.status.should eq(1)
        end
      end

      context "inheritance" do
        it "inherits from an instantiation" do
          counter = Test::Counter.new
          counter.should be_a(Test::IntBox)
          counter.increment
          counter.increment
          counter.get.should eq(2)
        end
      end
    end
  end
end
