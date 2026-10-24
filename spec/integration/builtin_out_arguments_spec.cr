require "./spec_helper"

describe "built-in out arguments" do
  it "works" do
    build_and_run("builtin_out_arguments") do
      class WideMeasurer < Test::Measurer
        def measure : {Bool, Int32}
          {false, 42}
        end
      end

      context "builtin_out_arguments: true" do
        it "returns an out pointer defaulting to nullptr with the result" do
          Test::Numbers.new.to_int.should eq({40, true})
          Test::Numbers.new.to_int(16).should eq({64, false})
        end

        it "returns several out pointers as a tuple" do
          Test::Numbers.new.get_date.should eq({2026, 10, 24})
        end

        it "takes and returns an in/out reference" do
          Test::Numbers.new.bump(1).should eq(2)
        end

        it "returns an enum" do
          Test::Numbers.new.convert(1.5).should eq({4.5, Test::Unit::Feet})
        end

        it "leaves buffers as pointers" do
          buffer = StaticArray(UInt8, 3).new(0)
          Test::Numbers.new.read(buffer.to_unsafe, 3).should eq(3)
          String.new(buffer.to_slice).should eq("abc")

          data = StaticArray(UInt8, 2).new(0)
          Test::Numbers.new.fill(data.to_unsafe, 2)
          data.should eq(StaticArray[1u8, 1u8])

          value = 0
          Test::Numbers.new.raw(pointerof(value).as(Void*))
          value.should eq(5)
        end

        it "follows out_arguments: false" do
          values = StaticArray(Float32, 2).new(0)
          Test::Numbers.new.copy_to(values.to_unsafe)
          values[1].should eq(2.5)
        end

        it "follows out_arguments: true" do
          Test::Numbers.new.read_byte.should eq({1, 'b'.ord.to_u8})
        end

        it "follows out_arguments: [indices]" do
          a = 1
          Test::Numbers.new.two(pointerof(a)).should eq(2)
          a.should eq(2)
        end
      end

      context "virtual override" do
        it "writes the override's tuple back through the pointer" do
          Test::Measurer.new.run.should eq("ok 10")
          Test::Ruler.new.run.should eq("ok 30")
          Test::Ruler.new.measure.should eq({true, 30})
          WideMeasurer.new.run.should eq("no 42")
          WideMeasurer.new.measure.should eq({false, 42})
        end
      end
    end
  end
end
