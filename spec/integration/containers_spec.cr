require "./spec_helper"

describe "container instantiation feature" do
  it "works" do
    build_and_run("containers") do
      FloatMatrix = Test::Std::Vector.of(Test::Std::Vector(Float64))

      context "sequential container" do
        it "works with explicitly instantiated container" do
          Test::Containers.new.integers.to_a.should eq([1, 2, 3])
        end

        it "works with auto instantiated container (result)" do
          Test::Containers.new.strings.to_a.should eq(["One", "Two", "Three"])
        end

        it "works with auto instantiated container (argument)" do
          list = [1.5, 2.5]
          Test::Containers.new.sum(list).should eq(4.0)
          Test::Containers.new.sum(Test::Std::Vector.of(Float64).from(list)).should eq(4.0)

          list = {3.5, 4.5}
          Test::Containers.new.sum(list).should eq(8.0)
          Test::Containers.new.sum(Test::Std::Vector.of(Float64).from(list)).should eq(8.0)
        end

        it "works with auto instantiated container (aliased container)" do
          Test::Containers.new.chars.to_a.should eq([1u8, 4u8, 9u8])
        end

        it "works with auto instantiated container (aliased element)" do
          Test::Containers.new.palette.to_a.should eq([0xFF0000u32, 0x00FF00u32, 0x0000FFu32])
        end

        it "works with nested containers" do
          Test::Containers.new.grid.map(&.to_a).should eq([[1, 4], [9, 16]])

          mat = FloatMatrix{
            [1.2, 3.4],
            [5.6, 7.8],
          }
          Test::Containers.new.transpose(mat).map(&.to_a).should eq([[1.2, 5.6], [3.4, 7.8]])
        end
      end
    end
  end
end
