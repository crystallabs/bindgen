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
      end

      subject = Test::Shapes.new

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
          {{ Test::Point.class.methods.map(&.name.stringify) }}.includes?("bg_discover").should be_false
          {{ Test::Shape.class.methods.map(&.name.stringify) }}.includes?("bg_discover").should be_true
        end

        it "wraps a Crystal sub-class instance in its wrapper class" do
          mine = MyTriangle.new
          subject.keep(mine)
          kept = subject.last.not_nil!
          kept.class.should eq(Test::Triangle)
          kept.to_unsafe.should eq(mine.to_unsafe)
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
