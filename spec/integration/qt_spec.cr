require "./spec_helper"

describe "Qt-specific wrapper features" do
  it "works" do
    build_and_run("qt") do
      module Test
        lib Binding
          struct ConvBinding
            x : Int32
          end
        end

        alias ConvBinding = Binding::ConvBinding

        module BindgenHelper
          def conv_to_crystal(x : Binding::ConvBinding) : ConvCrystal
            ConvCrystal.new
          end

          def conv_from_crystal(x : ConvCrystal) : Binding::ConvBinding
            Binding::ConvBinding.new x: 0
          end
        end
      end

      # Collects garbage, and allocates objects meanwhile, so the memory of
      # collected objects is reused.
      def collect_garbage
        10.times do
          GC.collect
          10.times { Test::QObject.new }
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

      # Overwrites the stack below its caller, so pointers to dead objects
      # left in it don't keep them alive.
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

      # Overrides a virtual method, so its constructor sets a jump table too.
      class KindObject < Test::QObject
        def kind : Int32
          2
        end
      end

      context "parent ownership" do
        it "keeps a child alive while its parent owns it" do
          window = Test::QObject.new
          leaving { Test::Label.new("child".to_unsafe, window); nil }

          collect_garbage
          window.child_count.should eq(1)
        end

        it "keeps an object given a parent by its constructor" do
          window = Test::QObject.new
          label = Test::Label.new("child".to_unsafe, window)
          child = Test::QObject.new(window)

          Test::BindgenHelper.kept_alive?(label).should be_true
          Test::BindgenHelper.kept_alive?(child).should be_true
          Test::BindgenHelper.kept_alive?(window).should be_false
          window.child_count.should eq(2)
        end

        it "doesn't keep an object without parent" do
          Test::BindgenHelper.kept_alive?(Test::QObject.new).should be_false
          Test::BindgenHelper.kept_alive?(Test::Label.new("orphan".to_unsafe)).should be_false
          Test::BindgenHelper.kept_alive?(Test::QObject.new(nil)).should be_false
        end

        it "keeps an object given a parent, and releases it given none" do
          window = Test::QObject.new
          label = Test::Label.new("orphan".to_unsafe)

          label.parent = window
          Test::BindgenHelper.kept_alive?(label).should be_true
          window.child_count.should eq(1)

          label.parent = nil
          Test::BindgenHelper.kept_alive?(label).should be_false
          window.child_count.should eq(0)
        end

        it "releases the children of a deleted parent" do
          window = Test::QObject.new
          label = Test::Label.new("child".to_unsafe, window)

          Test::QObject.delete_object(window)
          Test::BindgenHelper.kept_alive?(label).should be_false
        end

        it "releases the children of a parent the GC finalized" do
          label = nil
          leaving { label = Test::Label.new("child".to_unsafe, Test::QObject.new); nil }
          Test::BindgenHelper.kept_alive?(label.not_nil!).should be_true

          collect_garbage_until { !Test::BindgenHelper.kept_alive?(label.not_nil!) }
        end

        it "keeps a subclass overriding a virtual method alive" do
          window = Test::QObject.new
          object = KindObject.new(window)

          object.call_kind.should eq(2)
          Test::BindgenHelper.kept_alive?(object).should be_true
        end

        it "keeps a graphics item given a parent item" do
          parent = Test::QGraphicsItem.new
          item = Test::QGraphicsItem.new(parent)
          Test::BindgenHelper.kept_alive?(item).should be_true

          item.parent_item = nil
          Test::BindgenHelper.kept_alive?(item).should be_false

          item.parent_item = parent
          Test::BindgenHelper.kept_alive?(item).should be_true
        end

        it "ignores classes not deriving from an owning class" do
          window = Test::QObject.new
          unowned = Test::Unowned.new(window)
          Test::BindgenHelper.kept_alive?(unowned).should be_false

          unowned.parent = window
          Test::BindgenHelper.kept_alive?(unowned).should be_false
        end

        it "keeps an object by the parent_arguments: of its class" do
          tree = Test::Tree.new
          root = Test::TreeItem.new(tree)
          child = Test::TreeItem.new(root)
          other = Test::TreeItem.new(tree, root)
          Test::BindgenHelper.kept_alive?(root).should be_true
          Test::BindgenHelper.kept_alive?(child).should be_true
          Test::BindgenHelper.kept_alive?(other).should be_true
          Test::BindgenHelper.kept_alive?(Test::TreeItem.new).should be_false
          Test::BindgenHelper.kept_alive?(tree).should be_false
          tree.item_count.should eq(2)
          root.child_count.should eq(1)
        end

        it "keeps an item alive while its tree owns it" do
          tree = Test::Tree.new
          leaving { Test::TreeItem.new(Test::TreeItem.new(tree)); nil }

          collect_garbage
          tree.item_count.should eq(1)
        end

        it "releases the items of a tree the GC finalized" do
          root = Test::TreeItem.new
          leaving { root = Test::TreeItem.new(Test::Tree.new); nil }
          Test::BindgenHelper.kept_alive?(root).should be_true

          collect_garbage_until { !Test::BindgenHelper.kept_alive?(root) }
        end

        it "keeps an object kept alive after its parent is taken" do
          window = Test::QObject.new
          label = Test::Label.new("child".to_unsafe, window)
          Test::BindgenHelper.keep_alive(label)

          label.parent = nil
          Test::BindgenHelper.kept_alive?(label).should be_true # Kept alive still
          Test::BindgenHelper.release(label)
          Test::BindgenHelper.kept_alive?(label).should be_false
        end

        it "lets an object given a parent go when released" do
          window = Test::QObject.new
          label = Test::Label.new("child".to_unsafe, window)
          Test::BindgenHelper.keep_alive(label)

          Test::BindgenHelper.release(label) # Handed back: Its ownership ended too
          Test::BindgenHelper.kept_alive?(label).should be_false
        end

        it "releases an object kept alive and parented when it's deleted" do
          window = Test::QObject.new
          label = Test::Label.new("child".to_unsafe, window)
          Test::BindgenHelper.keep_alive(label)

          Test::QObject.delete_object(window)
          Test::BindgenHelper.kept_alive?(label).should be_false
        end

        it "doesn't keep an object C++ created" do
          window = Test::QObject.new
          object = Test::QObject.new_unmanaged
          Test::BindgenHelper.keep_alive(object)
          Test::BindgenHelper.kept_alive?(object).should be_false

          object.parent = window
          Test::BindgenHelper.kept_alive?(object).should be_false
          window.child_count.should eq(1)
          Test::QObject.delete_object(object)
        end
      end

      context "signal behaviour" do
        it "creates a on_X method" do
          subject = Test::SomeObject.new

          called = false
          subject.on_stuff_happened do
            called = true
          end

          called.should be_true
        end

        it "keeps the sender alive" do
          subject = Test::SomeObject.new
          Test::BindgenHelper.kept_alive?(subject).should be_false
          subject.on_stuff_happened { }
          Test::BindgenHelper.kept_alive?(subject).should be_true
        end

        it "rescues an exception of the block" do
          caught = [] of ::Exception
          default = Test::BindgenHelper.on_exception
          Test::BindgenHelper.on_exception = ->(e : ::Exception) { caught << e; nil }
          begin
            Test::SomeObject.new.on_stuff_happened { raise "in a slot" }
          ensure
            Test::BindgenHelper.on_exception = default
          end
          caught.map(&.message).should eq(["in a slot"])
        end

        it "types the block arguments as declared" do
          subject = Test::SomeObject.new

          # The mock emits default-constructed arguments: null pointers.
          subject.on_nullable_signal do |object|
            typeof(object).should eq(Test::SomeObject?)
            object.should be_nil
          end

          subject.on_object_signal do |object|
            typeof(object).should eq(Test::SomeObject)
            object.to_unsafe.null?.should be_true
          end
        end

        context "connection type" do
          it "defaults to an automatic connection" do
            subject = Test::SomeObject.new
            subject.on_stuff_happened { }
            Test::QObject.last_connection_type.should eq(Test::ConnectionType::AutoConnection)
          end

          it "takes the connection type" do
            subject = Test::SomeObject.new
            subject.on_stuff_happened(Test::ConnectionType::QueuedConnection) { }
            Test::QObject.last_connection_type.should eq(Test::ConnectionType::QueuedConnection)

            subject.on_stuff_happened(type: Test::ConnectionType::DirectConnection) { }
            Test::QObject.last_connection_type.should eq(Test::ConnectionType::DirectConnection)
          end

          it "takes the connection type after the type arguments of an overloaded signal" do
            subject = Test::SomeObject.new
            subject.on_overloaded(Int32, Bool, Test::ConnectionType::QueuedConnection) { |i, b| }
            Test::QObject.last_connection_type.should eq(Test::ConnectionType::QueuedConnection)
          end
        end

        context "context object" do
          it "is the sender without an application" do
            Test::QCoreApplication.instance.to_unsafe.null?.should be_true
            subject = Test::SomeObject.new
            subject.on_stuff_happened { }
            Test::QObject.last_context.should eq(subject.to_unsafe.as(Void*))
          end

          it "is the application" do
            app = Test::QCoreApplication.new
            subject = Test::SomeObject.new
            subject.on_stuff_happened { }
            Test::QObject.last_context.should eq(app.to_unsafe.as(Void*))
            Test::QObject.delete_object(app)
            Test::QCoreApplication.instance.to_unsafe.null?.should be_true
          end
        end

        context "overloaded signals" do
          it "creates methods for each overload" do
            subject = Test::SomeObject.new

            overload = 0
            subject.on_overloaded(Int32) do |i|
              i.should be_a(Int32)
              overload = 1
            end
            overload.should eq(1)
            subject.on_overloaded(Bool) do |b|
              b.should be_a(Bool)
              overload = 2
            end
            overload.should eq(2)
            subject.on_overloaded(Int32, Bool) do |i, b|
              i.should be_a(Int32)
              b.should be_a(Bool)
              overload = 3
            end
            overload.should eq(3)

            # check that tag-less overload isn't defined on Crystal: Each
            # takes the type arguments before the connection type.
            {{
              Test::SomeObject.methods.select do |method|
                method.name == "on_overloaded" && method.args.size <= 1
              end.size
            }}.should eq(0)
          end
        end

        context "ignored signals" do
          it "have no connection method" do
            {{ Test::SomeObject.methods.map(&.name.stringify) }}.includes?("ignored_signal").should be_false
            {{ Test::SomeObject.methods.map(&.name.stringify) }}.includes?("on_ignored_signal").should be_false
          end
        end

        context "private signals" do
          it "don't have an emission method" do
            {{ Test::SomeObject.methods.map(&.name.stringify) }}.includes?("private_signal").should be_false
          end

          it "have the connection method" do
            {{ Test::SomeObject.methods.map(&.name.stringify) }}.includes?("on_private_signal").should be_true
            {{ Test::SomeObject.methods.find(&.name.== "on_private_signal").args.map(&.name.stringify) }}.should eq(["type"])
          end
        end
      end

      context "hash and string conversion" do
        it "binds qHash as a method" do
          Test::Hashed.new(2).q_hash(0).should eq(62)
          Test::Hashed.new(2).q_hash(1).should eq(63)
        end

        it "forwards qHash to #hash, with #== from operator==" do
          Test::Hashed.new(2).hash.should eq(Test::Hashed.new(2).hash)
          Test::Hashed.new(2).hash.should_not eq(Test::Hashed.new(3).hash)
          table = {Test::Hashed.new(2) => "two"}
          table[Test::Hashed.new(2)].should eq("two")
          Set{Test::Hashed.new(1), Test::Hashed.new(1)}.size.should eq(1)
        end

        it "forwards toString to #to_s and #inspect" do
          Test::Hashed.new(7).to_s.should eq("Hashed 7")
          Test::Hashed.new(7).inspect.should eq("#<Test::Hashed Hashed 7>")
          "#{Test::Hashed.new(8)}".should eq("Hashed 8")
        end
      end

      context "Q_GADGET behaviour" do
        it "removes the gadget checker" do
          {{ Test::SomeGadget.methods.map(&.name.stringify) }}.includes?("qt_check_for_QGADGET_macro").should be_false
        end
      end
    end
  end
end
