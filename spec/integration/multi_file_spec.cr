require "./spec_helper"

describe "multi-file C++ output" do
  it "works" do
    build_and_run("multi_file", multi_file: true) do
      class Triangle < Test::Shape
        def sides : Int32
          3
        end
      end

      it "writes a file per class, and one of the shared declarations" do
        files = Dir.glob("tmp/multi_file.*.cpp").map { |path| File.basename(path) }.sort!
        files.should eq(%w[
          multi_file.bindgen_declarations.cpp
          multi_file.bindgen_functions.cpp
          multi_file.canvas.cpp
          multi_file.canvas__brush.cpp
          multi_file.container_std__vector_int_.cpp
          multi_file.shape.cpp
        ])
      end

      it "calls a method" do
        Test::Canvas::Brush.new.width.should eq(3)
      end

      it "calls a function outside of a class" do
        Test::Funcs.add(2, 3).should eq(5)
      end

      it "uses the type alias of a container" do
        Test::Canvas.new.sizes(3).to_a.should eq([10, 20, 30])
      end

      it "uses the structure of a virtual override" do
        Test::Shape.new.doubled_sides.should eq(0)
        Triangle.new.doubled_sides.should eq(6)
        Test::Canvas.new.measure(Triangle.new).should eq(3)
      end
    end
  end
end
