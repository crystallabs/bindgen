require "./spec_helper"

describe "C arrays in methods" do
  it "works" do
    build_and_run("c_arrays") do
      macro method_names(klass)
        {{ klass.resolve.methods.map(&.name.stringify) }}
      end

      context "array parameters" do
        it "takes a decayed array as pointer" do
          list = StaticArray[5, 6, 7, 8]
          Test::Arrays.new.first(list.to_unsafe).should eq(5)
        end

        it "takes a reference to an array as Slice" do
          Test::Arrays.new.sum(Slice[1, 2, 3, 4]).should eq(10)
          Test::Funcs.array_sum(Slice[1i16, 2i16, 3i16]).should eq(6)
        end

        it "writes into the Slice" do
          list = StaticArray(Int32, 4).new(0)
          Test::Arrays.new.fill(list.to_slice, 9)
          list.should eq(StaticArray[9, 9, 9, 9])
        end

        it "takes a multi-dimensional array as Slice of StaticArrays" do
          m = Slice[StaticArray[1f32, 0f32, 0f32], StaticArray[0f32, 2f32, 0f32], StaticArray[0f32, 0f32, 3f32]]
          Test::Arrays.new.trace(m).should eq(6f32)
        end

        it "takes a pointer to an array" do
          rows = StaticArray[StaticArray[1, 2, 3], StaticArray[4, 5, 6]]
          Test::Arrays.new.sum_rows(rows.to_unsafe, 2).should eq(21)
          Test::Arrays.new.corner(rows.to_unsafe).should eq(6)
        end

        it "takes nil for a pointer to an array defaulting to nullptr" do
          Test::Arrays.new.is_null.should be_true
          Test::Arrays.new.is_null(nil).should be_true
        end

        it "raises if the size doesn't match" do
          expect_raises(ArgumentError, "Expected a Slice of 4 elements, got 3") do
            Test::Arrays.new.sum(Slice[1, 2, 3])
          end
        end
      end

      context "array results" do
        it "returns a reference to an array as Slice" do
          arrays = Test::Arrays.new
          values = arrays.values_ref
          values.should be_a(Slice(Int32))
          values.should eq(Slice[1, 2, 3, 4])
          values[0] = 10
          arrays.values.should eq(Slice[10, 2, 3, 4])
        end

        it "returns a reference to a const array as read-only Slice" do
          matrix = Test::Arrays.new.matrix_ref
          matrix.should be_a(Slice(StaticArray(Float32, 3)))
          matrix.read_only?.should be_true
          matrix[1].should eq(StaticArray[4f32, 5f32, 6f32])
        end

        it "returns a pointer to an array" do
          arrays = Test::Arrays.new
          values = arrays.values_ptr
          values.should be_a(Pointer(StaticArray(Int32, 4)))
          values.value.should eq(StaticArray[1, 2, 3, 4])
        end

        it "returns a reference to a static array" do
          Test::Arrays.static_ref.should eq(Slice[7, 8])
        end
      end

      context "pointers to arrays as members" do
        it "has property methods" do
          arrays = Test::Arrays.new
          arrays.current.should be_a(Pointer(StaticArray(Int32, 4)))
          arrays.current.value.should eq(StaticArray[1, 2, 3, 4])

          other = StaticArray[5, 6, 7, 8]
          arrays.current = pointerof(other)
          arrays.current.value[3].should eq(8)
        end

        it "copies them into a lib struct" do
          rows = StaticArray[StaticArray[1, 2, 3], StaticArray[4, 5, 6]]
          grid = Test::Binding::Grid.new(rows: rows.to_unsafe, count: 2)
          typeof(grid.rows).should eq(Pointer(StaticArray(Int32, 3)))
          Test::Arrays.new.grid_sum(grid).should eq(21)
        end
      end

      it "skips unsupported methods" do
        names = method_names(Test::Arrays)
        names.should_not contain("unknown_bound")
        names.should_not contain("unknown_bound_ptr")
        names.should_not contain("items")
        names.should_not contain("items_ptr")
        names.should_not contain("nested")
        names.should_not contain("overridable")
      end
    end
  end
end
