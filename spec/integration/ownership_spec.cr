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
        fail "The GC didn't collect the objects in time: " \
             "#{Test::Dependent.destroyed} Dependent destroyed, " \
             "#{Test::Counted.alive} Counted alive, " \
             "#{Test::Mutual.destroyed} Mutual destroyed"
      end

      # Overwrites the stack below its caller.  The GC scans the stack
      # conservatively: A pointer to a dead object left in a slot of a frame
      # keeps the object alive until a later call overwrites the slot, and
      # which slots later calls overwrite depends on the platform.
      @[NoInline]
      def scrub_stack
        buffer = uninitialized UInt8[65536]
        buffer.to_slice.fill(0)
      end

      # Calls *block* in its own stack frame, and scrubs that frame afterwards,
      # so the GC can collect the objects the block left behind.
      def leaving(&block : -> Nil) : Nil
        block.call
        scrub_stack
      end

      # Creates a `Dependent` on a `Counted`, keeping neither.
      def leave_dependent
        leaving { Test::Dependent.new(Test::Counted.new) }
      end

      # Creates a `Dependent` on a `Counted` and a copy of it, keeping none.
      def leave_dependent_copy
        leaving { Test::Dependent.new(Test::Dependent.new(Test::Counted.new)) }
      end

      # Creates *count* pairs of objects owning each other, keeping none.
      def leave_pairs(count)
        leaving { count.times { Test::Mutual.new.pair_with(Test::Mutual.new) } }
      end

      # Releases *objects* while the table of kept objects is changing, as C++
      # deleting them in a GC finalizer run meanwhile would.  The releases are
      # queued, and done once the change is over.
      def Test::BindgenHelper.release_while_busy(objects)
        @@kept_alive_mutex.synchronize do
          change_kept_alive { objects.each { |object| release(object.to_unsafe) } }
        end
      end

      # Hands *counted* to a new `Owner`, which keeps it alive, and leaves the
      # owner behind.
      def leave_owner_of(counted)
        leaving { Test::Owner.new.adopt(counted) }
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

        it "applies the rules of the base class to a method a subclass re-declares" do
          inner = Test::Inner.new(12)
          Test::SubOuter.new_no_gc.store_inside(inner)
          Test::BindgenHelper.kept_alive?(inner).should be_true
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

        it "destroys a copy before the object it copies, and that before the arguments" do
          leave_dependent_copy
          Test::Counted.alive.should eq(1)

          collect_garbage_until { Test::Dependent.destroyed == 3 }
          Test::Dependent.counted_alive_at_destruction.should eq(1)

          collect_garbage_until { Test::Counted.alive == 0 }
        end
      end

      context "objects destroyed by C++" do
        it "skips the finalizer of an object its owner deleted" do
          leave_pairs(100)

          # The object of a pair finalized first deletes the other, whose
          # finalizer is queued: Each is destroyed exactly once.
          collect_garbage_until { Test::Mutual.destroyed == 200 }
          collect_garbage
          Test::Mutual.destroyed.should eq(200)
        end

        it "releases an object its owner deleted" do
          owner = Test::Owner.new
          counted = Test::Counted.new
          owner.adopt(counted)
          Test::BindgenHelper.kept_alive?(counted).should be_true

          alive = Test::Counted.alive
          owner.disown
          Test::Counted.alive.should eq(alive - 1)
          Test::BindgenHelper.kept_alive?(counted).should be_false
        end

        it "releases an object the finalizer of its owner deleted" do
          counted = Test::Counted.new
          leave_owner_of(counted)
          Test::BindgenHelper.kept_alive?(counted).should be_true

          alive = Test::Counted.alive
          collect_garbage_until { Test::Counted.alive == alive - 1 }
          Test::BindgenHelper.kept_alive?(counted).should be_false
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

        it "queues releases while the table changes" do
          objects = Array.new(200) { |i| Test::BindgenHelper.keep_alive(Test::Inner.new(i)) }
          objects.all? { |object| Test::BindgenHelper.kept_alive?(object) }.should be_true

          Test::BindgenHelper.release_while_busy(objects)
          objects.any? { |object| Test::BindgenHelper.kept_alive?(object) }.should be_false
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
