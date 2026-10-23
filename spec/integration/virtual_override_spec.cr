require "./spec_helper"

describe "C++ virtual overriding from Crystal feature" do
  it "works" do
    build_and_run("virtual_override") do
      # Test inheriting from abstract class
      class NameThing < Test::AbstractThing
        def name : UInt8*
          "NameThing".to_unsafe
        end
      end

      # Test inheriting from non-abstract, multiple-inheritance class
      class Thing < Test::Subclass
        def name : UInt8*
          "Thing".to_unsafe
        end

        def calc(a, b)
          a - b
        end
      end

      # Test overriding a method of the second base
      class SecondBaseThing < Test::Subclass
        def virtual_in_abstract_thing
          5
        end
      end

      class ImplicitThing < Test::Implicit
        # overrides Test::Base#calc (absent in Test::Implicit)
        def calc(a, b)
          a * b
        end
      end

      # The built-in structure of `Summer#sum`, see virtual_override.yml
      lib Test::Binding
        struct Triple
          a : Int64
          b : Int64
          c : Int64
        end
      end

      # Test a callback taking a structure larger than 16 bytes by value
      class Doubler < Test::Summer
        def sum(triple) : Int64
          (triple.a + triple.b + triple.c) * 2
        end

        def sum_ref(triple) : Int64
          (triple.a + triple.b + triple.c) * 3
        end
      end

      # Implements only the full overload of a pure method with a default
      # argument, like a Crystal model implementing `row_count(parent)`.
      class Tripler < Test::AbstractScalerMiddle
        def scaled(a : Int32, factor : Int32 = 2) : Int32
          a * factor * 3
        end

        # Only the full overload: `padded()` is concrete, calling C++ with
        # the default.
        def padded(pad : Int32) : Int32
          pad * 3
        end

        def extra : Int32
          0
        end
      end

      # A subclass of a concrete class below a private override of a method
      # with a default argument, like QStringListModel
      class Disc < Test::Circle
      end

      # Test constructing an abstract class with an implicit default constructor
      class Maker < Test::AbstractCreator
        def make : Int32
          42
        end
      end

      # Test subclassing a class whose base privately overrides a pure method
      class Oval < Test::AbstractRound
        def area : Int32
          sides + 40
        end
      end

      # Test overriding a virtual operator
      class LessThing < Test::Base
        def <(other) : Bool
          true
        end
      end

      # Test calling superclass method from overridden method
      class OverrideThing < Test::Base
        def calc(a, b)
          superclass.calc(a, b) ** 2
        end
      end

      class SubOverrideThing < Test::Subclass
        def calc(a, b)
          superclass.calc(a, b) ** 2
        end

        def has_random_number?
          superclass.has_random_number?
        end
      end

      class FinalMethodThing < Test::FinalMethod
        # can't override the `final` Test::FinalMethod#calc
        def calc(a, b)
          a * b
        end

        def random_number
          5
        end
      end

      # Test overriding only some overloads of a virtual method
      class FIntThing < Test::Overloads
        def f(x : Int32)
          10
        end
      end

      class FDoubleThing < Test::Overloads
        def f(x : Float64)
          20
        end
      end

      class FAnyThing < Test::Overloads
        def f(x)
          x.is_a?(Int32) ? 10 : 20
        end
      end

      class GThing < Test::Overloads
        def g
          30
        end
      end

      class HBoolThing < Test::Overloads
        # overloads the non-virtual `Test::Overloads#h(Bool)`
        def h(x : Bool)
          60
        end
      end

      class GrandparentThing < Test::Parent
        # overrides Test::Grandparent#in_grandparent
        def in_grandparent
          70
        end
      end

      class GreatGrandparentThing < Test::Child
        # overrides Test::Grandparent#in_grandparent, two levels up
        def in_grandparent
          700
        end
      end

      # Implements only the pure method, taking the default of the C++ base.
      class CrystalGreeter < Test::AbstractGreeter
        def greet(who : Test::Named? = nil) : Int32
          who ? who.id * 2 : -2
        end
      end

      # The pure method comes from the second C++ base, like `QGraphicsObject`.
      class CrystalGreeterObject < Test::GreeterObject
        def greet(who : Test::Named? = nil) : Int32
          who ? who.id * 3 : -3
        end
      end

      # Must be reopened because this type is private
      class Test::Subclass::Superclass
        def has_random_number?
          {{ @type.methods.map &.name.stringify }}.includes?("random_number")
        end
      end

      context "abstract class with an implicit default constructor" do
        it "is constructed by a Crystal subclass" do
          Maker.new.make.should eq(42)
        end
      end

      context "pure virtual method that can't be wrapped" do
        it "leaves the class without a C++ subclass, but usable" do
          {{ Test::Painter.abstract? }}.should be_true
          Test::SolidPainter.new.id.should eq(1)
          Test::SolidPainter.new.responds_to?(:draw).should be_false
        end
      end

      context "structure argument of a callback" do
        it "arrives intact" do
          Test::Summer.new.call_sum.should eq(6)
          Doubler.new.call_sum.should eq(12)
          Test::Summer.new.call_sum_ref.should eq(15) # Taken by reference
          Doubler.new.call_sum_ref.should eq(45)
        end
      end

      context "pure method with a default argument" do
        it "needs only the full overload implemented" do
          Tripler.new.scaled(2, 2).should eq(12)
          Tripler.new.scaled(2).should eq(12)
          Tripler.new.padded(3).should eq(9)
          Tripler.new.padded.should eq(6) # The default 2, through C++
        end
      end

      context "private override in a base" do
        it "is wrapped and the subclass works" do
          oval = Oval.new
          oval.sides.should eq(0)
          oval.sides(3).should eq(0) # The default argument's overload
          oval.area.should eq(40)
          Test::Shapes.sides_of(oval).should eq(0)
          Disc.new.sides.should eq(0)
        end
      end

      context "virtual operator" do
        it "is wrapped and overridable" do
          (Test::Base.new < Test::Base.new).should be_false
          Test::Base.new.less_than(Test::Base.new).should be_false
          LessThing.new.less_than(Test::Base.new).should be_true # Through C++
        end
      end

      context "non-abstract base-class" do
        it "overrides virtual method" do
          Thing.new.calc(10, 4).should eq(10 - 4)
        end

        it "overrides pure method" do
          String.new(Thing.new.name).should eq("Thing")
        end

        it "can call non-overriden virtual method" do
          Thing.new.random_number.should eq(4)
        end

        it "can call non-virtual method" do
          Thing.new.normal_method.should eq(1)
        end

        it "allows calling Crystal overrides from C++" do
          Thing.new.call_virtual(7, 6).should eq(1)
        end

        it "can call superclass method from overridden method" do
          OverrideThing.new.calc(10, 4).should eq(196)
          SubOverrideThing.new.calc(10, 4).should eq(1600)
        end

        it "can override implicitly inherited method" do
          ImplicitThing.new.call_virtual(7, 6).should eq(42)
        end

        it "can call methods of second base" do
          Thing.new.normal_method_in_abstract_thing.should eq(1)
          Thing.new.virtual_in_abstract_thing.should eq(2)
          String.new(Thing.new.itself.name).should eq("Thing")
        end

        it "allows calling Crystal overrides of second base from C++" do
          SecondBaseThing.new.call_virtual_in_abstract_thing.should eq(5)
          SecondBaseThing.new.as_abstract_thing.call_virtual_in_abstract_thing.should eq(5)
        end

        it "auto wraps into an instance" do
          thing = Thing.new
          base = thing.belong_to_us
          base.should be_a(Test::Base)
          base.calc(4, 5).should eq(-1)
        end
      end

      context "abstract base-class" do
        it "can call overriden pure method" do
          String.new(NameThing.new.name).should eq("NameThing")
        end

        it "can call a member method" do
          NameThing.new.normal_method_in_abstract_thing.should eq(1)
        end

        it "auto wraps into an instance" do
          thing = NameThing.new
          abstract_base = thing.itself
          abstract_base.should be_a(Test::AbstractThing)
          String.new(abstract_base.name).should eq("NameThing")
        end
      end

      context "superclass opt-out" do
        it "can opt out generation of superclass wrappers" do
          {{ Test::Skip.has_constant?("Superclass") }}.should be_false
          {{ Test::Skip.methods.map(&.name.stringify) }}.includes?("superclass").should be_false
        end

        it "can opt out generation of methods in superclass wrappers" do
          SubOverrideThing.new.has_random_number?.should be_false
        end
      end

      context "final" do
        it "doesn't sub-class a final class" do
          {{ Test::FinalClass.has_constant?("Superclass") }}.should be_false
          Test::FinalClass.new.calc(10, 4).should eq(6)
        end

        it "doesn't override a final method" do
          FinalMethodThing.new.call_virtual(10, 4).should eq(6)
        end

        it "overrides other virtual methods" do
          FinalMethodThing.new.call_random_number.should eq(5)
        end
      end

      context "overloaded virtual methods" do
        it "only overrides overloads with matching argument types" do
          FIntThing.new.call_f_int.should eq(10)
          FIntThing.new.call_f_double.should eq(2)
          FDoubleThing.new.call_f_int.should eq(1)
          FDoubleThing.new.call_f_double.should eq(20)
        end

        it "overrides all overloads with an unrestricted method" do
          FAnyThing.new.call_f_int.should eq(10)
          FAnyThing.new.call_f_double.should eq(20)
        end

        it "overrides only the non-const overload" do
          GThing.new.call_g.should eq(30)
          GThing.new.call_g_const.should eq(4)
        end

        it "doesn't override a virtual method by a non-virtual overload" do
          HBoolThing.new.call_h_int.should eq(5)
          HBoolThing.new.call_h_bool.should eq(6)
        end
      end

      context "indirect base-class" do
        it "overrides method of a grandparent class" do
          GrandparentThing.new.call_in_grandparent.should eq(70)
          Test::Parent.new.call_in_grandparent.should eq(7)
          GreatGrandparentThing.new.call_in_grandparent.should eq(700)
        end

        it "implements pure methods of a second base in the Impl class" do
          {{ Test::AbstractSecond.abstract? }}.should be_true
          {{ Test::AbstractSecondImpl.has_method?("name") }}.should be_true
        end

        it "implements pure methods of a grandparent in the Impl class" do
          {{ Test::AbstractLeafImpl.has_method?("pure") }}.should be_true
        end

        it "names the arguments of an override like the overridden method" do
          {% begin %}
            {% method = Test::UnnamedArgument.methods.find(&.name.== "named") %}
            {{ method.args.first.name.stringify }}.should eq("value")
            {% method = Test::UnnamedArgument.methods.find(&.name.== "unnamed") %}
            {{ method.args.first.name.stringify }}.should eq("unnamed_arg_0")
          {% end %}
        end
      end

      context "override without the default argument of the overridden method" do
        it "takes the default of the overridden method" do
          named = Test::Named.new(4)

          Test::PoliteGreeter.new.greet.should eq(-10)
          Test::PoliteGreeter.new.greet(named).should eq(40)
          Test::TextGreeter.new.greet.should eq(-100)
          Test::TextGreeter.new.greet(nil).should eq(-100)
          Test::TextGreeter.new.greet(named).should eq(400)
          Test::TextGreeter.new.greet_nobody.should eq(-100)
        end

        it "lets a Crystal subclass implement only the pure method" do
          CrystalGreeter.new.greet_nobody.should eq(-2)
          CrystalGreeterObject.new.greet_nobody.should eq(-3)
          CrystalGreeterObject.new.greet.should eq(-3)
        end
      end

      context "namespaced classes" do
        it "compiles" do
          Test::Module::SuperV.new.f
        end
      end

      it "supports classes whose virtual methods are all filtered" do
        Test::OnlyFilteredVirtuals.new.value.should eq(8)
      end
    end
  end
end
