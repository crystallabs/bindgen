require "./spec_helper"

describe "function pointer members of copied structures" do
  it "works" do
    build_and_run("function_pointers") do
      it "copies them as Procs" do
        ops = Test::Funcs.make
        typeof(ops.add).should eq(Proc(Int32, Int32, Int32))
        typeof(ops.clear).should eq(Proc(Pointer(Test::Binding::Point), Nil))
        ops.add.call(3, 4).should eq(7)
        ops.negate.call(5).should eq(-5)
      end

      it "passes copied structures" do
        ops = Test::Funcs.make
        point = Test::Binding::Point.new(x: 1, y: 2)
        ops.clear.call(pointerof(point))
        point.x.should eq(0)
        point.y.should eq(0)
        ops.sum.call(Test::Binding::Point.new(x: 3, y: 4)).should eq(7)
      end

      it "passes function pointers as Void pointers" do
        ops = Test::Funcs.make
        typeof(ops.apply).should eq(Proc(Pointer(Void), Int32, Int32, Int32))
        ops.apply.call(ops.add.pointer, 30, 4).should eq(34)
      end

      it "calls Procs set in Crystal from C++" do
        ops = Test::Funcs.make
        ops.negate = ->(value : Int32) { value * 10 }
        Test::Funcs.call_negate(ops, 4).should eq(40)
      end

      it "uses Void pointers for those Crystal can't call" do
        ops = Test::Funcs.make
        typeof(ops.variadic).should eq(Pointer(Void))
        typeof(ops.foreign).should eq(Pointer(Void))
        typeof(ops.converted).should eq(Pointer(Void))
        typeof(ops.table).should eq(StaticArray(Pointer(Void), 2))
        typeof(ops.indirect).should eq(Pointer(Pointer(Void)))
        ops.table[0].should eq(ops.add.pointer)
        ops.indirect.value.should eq(ops.add.pointer)
      end

      it "keeps them out of wrapper classes" do
        subject = Test::Funcs.callbacks
        subject.value.should eq(7)
        subject.responds_to?(:twice).should be_false
        subject.to_unsafe.value.twice.call(4).should eq(8)
      end

      it "lays them out like C++" do
        sizeof(Test::Binding::Ops).should eq(Test::Funcs.size)
        offsetof(Test::Binding::Ops, @indirect).should eq(Test::Funcs.offset_indirect)
      end
    end
  end
end
