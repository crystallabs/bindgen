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
          Test::Containers.new.brightest([1u32, 3u32, 2u32]).should eq(3u32)
          Test::Containers.new.palettes.map(&.to_a).should eq([[0xFF0000u32], [0x00FF00u32, 0x0000FFu32]])
        end

        it "instantiates a container of an aliased element only once" do
          # `std::vector<rgb>` and `std::vector<unsigned int>` are both used and
          # both configured, and are the same type.  There must be as many
          # wrappers of it as of `std::vector<int>`, which is one per standard
          # library namespace.
          wrappers = {{ Test.constants.map(&.stringify).select(&.starts_with?("Container_")) }}
          wrappers.count(&.includes?("rgb")).should eq(0)
          wrappers.count(&.ends_with?("vector_unsigned_int_")).should eq(wrappers.count(&.ends_with?("vector_int_")))

          Test::Containers.new.palette.class.should eq(Test::Containers.new.numbers.class)
          Test::Containers.new.numbers.to_a.should eq([1u32, 2u32, 3u32])
          Test::Containers.new.brightest(Test::Std::Vector.of(UInt32).from([4u32, 5u32])).should eq(5u32)
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
