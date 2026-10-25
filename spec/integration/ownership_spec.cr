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
             "#{Test::VirtualDependent.destroyed} VirtualDependent destroyed, " \
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
        kept_alive_synchronize do
          change_kept_alive { objects.each { |object| release(object.to_unsafe) } }
        end
      end

      # Runs the block holding the lock of the kept objects, as a change of the
      # table does.
      def Test::BindgenHelper.holding_kept_alive(&)
        kept_alive_synchronize { yield }
      end

      # Hands *counted* to a new `Owner`, which keeps it alive, and leaves the
      # owner behind.
      def leave_owner_of(counted)
        leaving { Test::Owner.new.adopt(counted) }
      end

      # A Crystal subclass overriding a virtual method: the C++ object calls
      # the override on the Crystal object it looks up, without referring to it,
      # so the instance is collectable like any other object.
      class KindTwo < Test::VirtualDependent
        def kind : Int32
          2
        end
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

      context "release:" do
        it "releases the result of a method handing an object back" do
          owner = Test::Owner.new
          child = Test::Counted.new
          owner.adopt(child)
          Test::BindgenHelper.kept_alive?(child).should be_true

          taken = owner.take_child
          taken.to_unsafe.should eq(child.to_unsafe)
          Test::BindgenHelper.kept_alive?(child).should be_false

          owner.adopt(taken)
          owner.disown # Deletes it, so later counts of `Counted` are unaffected
        end

        it "releases the argument of a method handing an object back" do
          owner = Test::Owner.new
          child = Test::Counted.new
          owner.adopt(child)

          owner.remove_child(child)
          Test::BindgenHelper.kept_alive?(child).should be_false

          owner.adopt(child)
          owner.disown
        end

        it "releases the selected arguments, keeping others" do
          owner = Test::Owner.new
          old = Test::Counted.new
          replacement = Test::Counted.new
          owner.adopt(old)

          owner.swap_child(old, replacement).to_unsafe.should eq(old.to_unsafe)
          Test::BindgenHelper.kept_alive?(old).should be_false
          Test::BindgenHelper.kept_alive?(replacement).should be_true

          owner.disown
          owner.adopt(old)
          owner.disown
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

      context "depends_on: of a method" do
        # Holds dependents, so a spec can drop them without leaving pointers
        # to them on the stack.
        dependents = [] of Test::Dependent | Test::VirtualDependent

        it "replaces the dependencies of the object" do
          Test::Counted.alive.should eq(0)
          destroyed = Test::Dependent.destroyed
          leaving { dependents << Test::Dependent.new(Test::Counted.new) }
          leaving { dependents[0].retarget(Test::Counted.new) }
          Test::Counted.alive.should eq(2)

          # The old argument is collected, the new one lives on with the object.
          collect_garbage_until { Test::Counted.alive == 1 }
          collect_garbage
          Test::Counted.alive.should eq(1)
          Test::Dependent.destroyed.should eq(destroyed)

          # Dropped, the object is destroyed before the new argument.
          dependents.clear
          scrub_stack
          collect_garbage_until { Test::Dependent.destroyed == destroyed + 1 }
          Test::Dependent.counted_alive_at_destruction.should eq(1)
          collect_garbage_until { Test::Counted.alive == 0 }
        end

        it "clears the dependencies with a null argument" do
          leaving { dependents << Test::Dependent.new(Test::Counted.new) }
          # Through the binding, as the wrapper takes no `nil`.
          leaving { Test::Binding.bg_Dependent_retarget_Counted_X(dependents[0].as(Test::Dependent), Pointer(Test::Binding::Counted).null) }
          collect_garbage_until { Test::Counted.alive == 0 }
          dependents.clear
        end

        it "works through the wrapper of a shadow subclass" do
          Test::Counted.alive.should eq(0)
          destroyed = Test::VirtualDependent.destroyed
          leaving { dependents << Test::VirtualDependent.new.tap(&.retarget(Test::Counted.new)) }
          leaving { dependents[0].retarget(Test::Counted.new) }
          leaving do
            dependent = dependents[0].as(Test::VirtualDependent)
            dependent.call_kind.should eq(1)
            Test::Layout.at_base(dependent).should be_true
          end

          collect_garbage_until { Test::Counted.alive == 1 }
          collect_garbage
          Test::VirtualDependent.destroyed.should eq(destroyed)

          dependents.clear
          scrub_stack
          collect_garbage_until { Test::VirtualDependent.destroyed == destroyed + 1 }
          Test::VirtualDependent.counted_alive_at_destruction.should eq(1)
          collect_garbage_until { Test::Counted.alive == 0 }
        end

        it "finds the object at the start of its allocation" do
          counted = Test::Counted.new
          dependent = Test::Dependent.new(counted)
          Test::Layout.at_base(dependent).should be_true
          Test::Layout.is_binding_object(dependent).should be_true
        end

        it "does nothing on an object C++ created" do
          counted = Test::Counted.new
          other = Test::Counted.new
          dependent = Test::Dependent.new_no_gc(counted)
          Test::Layout.is_binding_object(dependent).should be_false

          dependent.retarget(other)
          dependent.target.to_unsafe.should eq(other.to_unsafe)
          Test::Dependent.targets(dependent, other).should be_true
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

      context "keyed by the GC allocation" do
        it "finds an object kept through its second base" do
          dual = Test::Dual.new
          second = dual.as_second
          second.to_unsafe.address.should_not eq(dual.to_unsafe.address)

          Test::BindgenHelper.keep_alive(second)
          Test::BindgenHelper.kept_alive?(dual).should be_true
          Test::BindgenHelper.kept_alive?(second).should be_true

          Test::BindgenHelper.release(dual)
          Test::BindgenHelper.kept_alive?(second).should be_false
        end

        it "releases an object kept through its second base when C++ deletes it" do
          dual = Test::Dual.new
          second = dual.as_second
          Test::BindgenHelper.keep_alive(second)

          Test::Dual.delete_dual(dual)
          Test::BindgenHelper.kept_alive?(second).should be_false
        end

        it "doesn't keep an object C++ created" do
          outer = Test::Outer.new_no_gc # Uncollectable memory of libgccpp's operator new
          Test::BindgenHelper.keep_alive(outer).should be(outer)
          Test::BindgenHelper.kept_alive?(outer).should be_false
          Test::BindgenHelper.release(outer.to_unsafe) # Does nothing either
        end
      end

      context "an instance of a Crystal subclass overriding a virtual method" do
        # Holds holders, so a spec can drop them without leaving pointers to
        # them on the stack.
        holders = [] of Test::Holder

        it "is collected once Crystal drops it" do
          destroyed = Test::VirtualDependent.destroyed
          leaving { KindTwo.new.call_kind.should eq(2) }
          collect_garbage_until { Test::VirtualDependent.destroyed == destroyed + 1 }
        end

        it "lives on with an object depending on it, with its overrides" do
          destroyed = Test::VirtualDependent.destroyed
          leaving { holders << Test::Holder.new(KindTwo.new) }
          collect_garbage
          Test::VirtualDependent.destroyed.should eq(destroyed)
          holders[0].kind_of_held.should eq(2) # The override, not the C++ method

          # Dropped, the object is destroyed before the dependency.
          holders.clear
          scrub_stack
          collect_garbage_until { Test::VirtualDependent.destroyed == destroyed + 1 }
        end

        it "lives on while kept alive, with its overrides" do
          destroyed = Test::VirtualDependent.destroyed
          pointer = Pointer(Test::Binding::VirtualDependent).null
          leaving { pointer = Test::BindgenHelper.keep_alive(KindTwo.new).to_unsafe }
          collect_garbage
          Test::VirtualDependent.destroyed.should eq(destroyed)

          # A new wrapper of the C++ object: its virtual method reaches the
          # override of the kept Crystal object.
          Test::VirtualDependent.new(unwrap: pointer).call_kind.should eq(2)

          Test::BindgenHelper.release(pointer)
          pointer = Pointer(Test::Binding::VirtualDependent).null
          scrub_stack
          collect_garbage_until { Test::VirtualDependent.destroyed == destroyed + 1 }
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

        it "releases from a thread without a scheduler while the table is locked" do
          # The GC runs a finalizer on the thread allocating, which may run no
          # scheduler, like the monitor thread of the execution contexts: the
          # release there must wait for the lock, not suspend a fiber.
          inner = Test::Inner.new(9)
          Test::BindgenHelper.keep_alive(inner)

          thread = nil
          Test::BindgenHelper.holding_kept_alive do
            thread = Thread.new { Test::BindgenHelper.release(inner) }
            deadline = Time.monotonic + 20.milliseconds
            while Time.monotonic < deadline
            end
          end
          thread.as(Thread).join # Raises what the thread raised
          Test::BindgenHelper.kept_alive?(inner).should be_false
        end

        it "destroys an object finalized in another thread in the main thread" do
          # The GC runs a finalizer on the thread allocating, and the objects of
          # a library like Qt must be destroyed in the thread they live in: a
          # finalizer in another thread queues its object for the main thread,
          # which destroys it with the next finalizer it runs, or on request.
          alive = Test::Counted.alive
          leaving { Test::Counted.new }

          finalized_elsewhere = false
          50.times do
            Thread.new { collect_garbage }.join
            finalized_elsewhere = Test::Counted.alive == alive + 1
            Test::BindgenHelper.destroy_pending
            break if Test::Counted.alive == alive
          end
          Test::Counted.alive.should eq(alive)
          finalized_elsewhere.should be_true
        end

        it "ignores nil" do
          Test::BindgenHelper.keep_alive(nil).should be_nil
        end
      end
    end

    # Static methods have no object to store dependencies in.
    ToolLog.warnings.should contain("depends_on: of Dependent ignores targets: it has no object")
  end
end
