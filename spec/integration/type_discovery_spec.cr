require "./spec_helper"

describe "type discovery feature" do
  it "works" do
    build_and_run("type_discovery") do
      class Visitor < Test::Shapes
        getter seen = [] of String

        def visit(shape : Test::Shape) : String
          @seen << shape.class.name
          "visited " + shape.name
        end

        def visit_ref(shape : Test::Shape) : String
          @seen << shape.class.name
          super
        end
      end

      class MyTriangle < Test::Triangle
        property note = "mine"
      end

      class MyLabelled < Test::Labelled
      end

      # A class the binding can't name, and a subclass of a subclass.
      private class PrivateTriangle < MyTriangle
      end

      # Counts its collected instances.  No override: an override's closure in
      # the C++ object refers to the Crystal object, a finalization cycle.
      # The `name` the compiler copies into it, once `name` was called on a
      # `Shape`, must not count as one.
      class Counted < Test::Triangle
        class_property collected = 0

        def finalize
          Counted.collected += 1
        end
      end

      subject = Test::Shapes.new

      # Overwrites the stack below its caller, so pointers to dead objects
      # left in it don't keep them alive.
      @[NoInline]
      def scrub_stack
        buffer = uninitialized UInt8[65536]
        buffer.to_slice.fill(0)
      end

      # Collects garbage, and allocates objects meanwhile, so the memory of
      # collected objects is reused.  Scrubs the stack first: the block of
      # `collect_garbage_until` left the object it looked at there.
      def collect_garbage
        10.times do
          scrub_stack
          GC.collect
          10.times { Test::Point.new }
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

      # Calls *block* in its own stack frame, and scrubs that frame afterwards.
      def leaving(&block : -> Nil) : Nil
        block.call
        scrub_stack
      end

      # Gives *subject* new `Counted`s to keep, in a frame of its own, so no
      # register of the caller holds a Crystal object.
      @[NoInline]
      def keep_counted(subject, count) : Nil
        count.times { |index| subject.keep_at(index, Counted.new) }
      end

      context "pointer results" do
        it "wraps in the class of the dynamic type" do
          shape = subject.triangle
          shape.class.should eq(Test::Triangle)
          shape.as(Test::Triangle).area.should eq(6)
          shape.name.should eq("triangle")
          typeof(shape).should eq(Test::Shape)
        end

        it "wraps an unwrapped sub-class in the nearest wrapped class" do
          shape = subject.rectangle
          shape.class.should eq(Test::Polygon)
          shape.as(Test::Polygon).corners.should eq(4)
          shape.name.should eq("rectangle")

          # Found by walking the casts once, then remembered.
          subject.rectangle.class.should eq(Test::Polygon)
        end

        it "wraps in the Impl class of an abstract class" do
          subject.circle.class.should eq(Test::Circle)
          subject.round.class.should eq(Test::Circle)
          subject.round.radius.should eq(1.5)
        end

        it "wraps the declared class as is" do
          subject.shape.class.should eq(Test::Shape)
          subject.none.should be_nil
          subject.last.should be_nil
        end

        it "discovers a class with a second base through the Crystal superclass" do
          shape = subject.labelled
          shape.class.should eq(Test::Labelled)
          shape.as(Test::Labelled).as_named.label.should eq("labelled")

          # The second base isn't a Crystal superclass of Labelled.
          named = subject.named
          named.class.should eq(Test::Named)
          named.label.should eq("labelled")
        end

        it "doesn't discover through a non-polymorphic class" do
          subject.point3.class.should eq(Test::Point)
        end

        it "doesn't share wrappers of objects C++ constructed" do
          subject.triangle.should_not be(subject.triangle)
        end
      end

      context "objects constructed from Crystal" do
        it "are returned as the Crystal object" do
          mine = MyTriangle.new
          mine.note = "kept"
          subject.keep(mine)
          kept = subject.last.as(Test::Shape)
          kept.should be(mine)
          kept.as(MyTriangle).note.should eq("kept")
          typeof(kept).should eq(Test::Shape)

          plain = Test::Triangle.new
          subject.keep(plain)
          subject.last.should be(plain)
          subject.last.as(Test::Shape).to?(Test::Polygon).should be(plain)

          secret = PrivateTriangle.new
          subject.keep(secret)
          subject.last.should be(secret)
        end

        it "are returned as the Crystal object through a class without discovery" do
          point = Test::Point3.new
          subject.keep_point(point)
          subject.last_point.should be(point)
          typeof(subject.last_point.as(Test::Point)).should eq(Test::Point)

          other = Test::Point.new
          subject.keep_point(other)
          subject.last_point.should be(other)
        end

        it "wrap a secondary base anew" do
          labelled = MyLabelled.new
          subject.keep(labelled)
          subject.last.should be(labelled)

          named = subject.last_named.as(Test::Named)
          named.class.should eq(Test::Named)
          named.label.should eq("labelled")
          named.should_not be(labelled)
        end

        it "don't claim a copy" do
          mine = MyTriangle.new
          subject.keep(mine)
          copy = subject.copy_last
          copy.should_not be(mine)
          copy.class.should eq(Test::Shape)
        end

        it "get a new wrapper once the Crystal object is collected" do
          # The C++ objects stay alive: `subject`, an allocation the GC scans,
          # points to them.  The Crystal objects are only referenced weakly.
          # Several objects, as a stale word somewhere the GC scans may keep
          # one; the block mustn't touch them: a register would keep one.
          collected = Counted.collected
          leaving { keep_counted(subject, 32) }
          collect_garbage_until { Counted.collected > collected }

          classes = (0...32).map { |index| subject.kept_at(index).class }
          classes.should contain(Test::Triangle)
          classes.each { |klass| [Test::Triangle, Counted].should contain(klass) }
        end
      end

      context "reference results" do
        it "wraps in the class of the dynamic type" do
          subject.triangle_ref.class.should eq(Test::Triangle)
        end

        it "doesn't discover a copy" do
          subject.triangle_value.class.should eq(Test::Shape)
        end
      end

      context "#to?" do
        it "wraps in the class of the dynamic type" do
          subject.triangle.to?(Test::Polygon).class.should eq(Test::Triangle)
          subject.circle.to?(Test::Round).class.should eq(Test::Circle)
          subject.triangle.to?(Test::Round).should be_nil
        end
      end

      context "callback arguments" do
        it "are discovered" do
          visitor = Visitor.new
          visitor.visit_triangle.should eq("visited triangle")
          visitor.visit_circle_ref.should eq("circle")
          visitor.seen.should eq(["Test::Triangle", "Test::Circle"])
        end
      end
    end
  end
end
