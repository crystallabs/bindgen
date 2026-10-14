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

      class ImplicitThing < Test::Implicit
        # overrides Test::Base#calc (absent in Test::Implicit)
        def calc(a, b)
          a * b
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

      # Must be reopened because this type is private
      class Test::Subclass::Superclass
        def has_random_number?
          {{ @type.methods.map &.name.stringify }}.includes?("random_number")
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

        # TODO: This fails!
        pending "can call method of second base" do
          # Thing.new.normal_method_in_abstract_thing.should eq(1)
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

      context "namespaced classes" do
        it "compiles" do
          Test::Module::SuperV.new.f
        end
      end
    end
  end
end
