require "./spec_helper"

describe "keeping objects passed to C++ alive" do
  it "works" do
    build_and_run("ownership") do
      # Collects garbage, and allocates objects of the same size meanwhile, so
      # the memory of collected objects is reused.
      def collect_garbage
        10.times do
          GC.collect
          10.times { Test::Inner.new(-1) }
        end
        GC.collect
      end

      # Collects garbage until the block returns true, or fails.
      def collect_garbage_until(&)
        50.times do
          return if yield
          collect_garbage
        end
        fail "The GC didn't collect the objects in time"
      end

      # Creates a `Dependent` on a `Counted`, keeping neither.
      def leave_dependent
        Test::Dependent.new(Test::Counted.new)
        nil
      end

      # Stores a new `Inner` in a new `Outer`, which doesn't keep it alive by
      # itself.  Returns if the `Inner` is kept alive.
      def store_inner(x)
        inner = Test::Inner.new(x)
        Test::Outer.new_no_gc.inside = inner
        Test::BindgenHelper.kept_alive?(inner)
      end

      context "keep_alive: [patterns]" do
        it "keeps the argument of a setter alive" do
          store_inner(7).should be_true
          collect_garbage
          Test::Outer.last.inside.x.should eq(7)
        end

        it "keeps the argument of a method alive" do
          Test::Outer.new_no_gc.store_inside(Test::Inner.new(8))
          Test::Outer.new_no_gc.store_other(Test::Inner.new(9))
          collect_garbage
          Test::Outer.last.other.x.should eq(9)
        end

        it "skips arguments wrapped as a Crystal struct" do
          plain = Test::Plain.new
          Test::Outer.new_no_gc.store_plain(pointerof(plain))
        end

        it "ignores other methods" do
          inner = Test::Inner.new(10)
          Test::Outer.new_no_gc.sum(inner, 1).should eq(11)
          Test::BindgenHelper.kept_alive?(inner).should be_false
        end
      end

      context "keep_alive: {pattern: indices}" do
        it "keeps the selected arguments alive" do
          outer = Test::Outer.new_no_gc
          inner = Test::Inner.new(1)
          other = Test::Inner.new(2)
          Test::Picky.new.set_both(outer, inner, other)

          Test::BindgenHelper.kept_alive?(outer).should be_false
          Test::BindgenHelper.kept_alive?(inner).should be_false
          Test::BindgenHelper.kept_alive?(other).should be_true
        end

        it "keeps the arguments of a constructor alive" do
          inner = Test::Inner.new(4)
          Test::Picky.new(inner).kept.x.should eq(4)
          Test::BindgenHelper.kept_alive?(inner).should be_true
        end

        it "keeps nothing alive with false" do
          inner = Test::Inner.new(1)
          Test::Picky.new.set_none(Test::Outer.new_no_gc, inner)
          Test::BindgenHelper.kept_alive?(inner).should be_false
        end
      end

      context "depends_on: [patterns]" do
        it "destroys the object before the arguments of its constructor" do
          leave_dependent
          Test::Counted.alive.should eq(1)

          collect_garbage_until { Test::Dependent.destroyed == 1 }
          Test::Dependent.counted_alive_at_destruction.should eq(1)

          # The argument is collected once the object depending on it is gone.
          collect_garbage_until { Test::Counted.alive == 0 }
        end
      end

      context "BindgenHelper" do
        it "releases a kept object" do
          inner = Test::Inner.new(3)
          Test::BindgenHelper.keep_alive(inner).should be(inner)
          Test::BindgenHelper.kept_alive?(inner).should be_true

          Test::BindgenHelper.release(inner).should be(inner)
          Test::BindgenHelper.kept_alive?(inner).should be_false
        end

        it "releases a kept object through another wrapper" do
          store_inner(5).should be_true
          inside = Test::Outer.last.inside # A new wrapper of the same C++ object
          Test::BindgenHelper.kept_alive?(inside).should be_true

          Test::BindgenHelper.release(inside)
          Test::BindgenHelper.kept_alive?(Test::Outer.last.inside).should be_false
        end

        it "releases by pointer" do
          inner = Test::Inner.new(7)
          Test::BindgenHelper.keep_alive(inner)
          Test::BindgenHelper.release(inner.to_unsafe)
          Test::BindgenHelper.kept_alive?(inner).should be_false
        end

        it "ignores nil" do
          Test::BindgenHelper.keep_alive(nil).should be_nil
        end
      end
    end
  end
end
