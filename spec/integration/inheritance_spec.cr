require "./spec_helper"

describe "single and multiple inheritance feature" do
  it "works" do
    build_and_run("inheritance") do
      it "sets the base-class correctly" do
        {{ Test::AbstractThing.superclass == Reference }}.should be_true
        {{ Test::Subclass.superclass == Test::Base }}.should be_true
        {{ Test::Base.superclass == Reference }}.should be_true
      end

      context "namespaced classes" do
        it "sets the base-class correctly" do
          {{ Test::Module::Derived1.superclass == Test::Super1 }}.should be_true
          {{ Test::Derived2.superclass == Test::Module::Super2 }}.should be_true
          {{ Test::Module::Derived3.superclass == Test::Module::Super3 }}.should be_true
        end
      end

      it "sets the abstract class attribute" do
        {{ Test::AbstractThing.abstract? }}.should be_true
        {{ Test::Subclass.abstract? }}.should be_false
        {{ Test::Base.abstract? }}.should be_false
      end

      it "adds Subclass#as_abstract_thing" do
        {{ Test::Subclass.methods.map(&.name.stringify) }}.includes?("as_abstract_thing").should be_true
      end

      it "can call C++ virtual methods" do
        Test::Base.new.calc(4, 5).should eq(9)
        Test::Subclass.new.calc(4, 5).should eq(20)
        String.new(Test::Subclass.new.name).should eq("Hello")
      end

      it "can call methods of second base" do
        Test::Subclass.new.normal_method_in_abstract_thing.should eq(1)
        Test::Subclass.new.virtual_in_abstract_thing.should eq(2)
      end

      it "adds shadow-impl class for abstract classes" do
        {{ Test::AbstractThingImpl.superclass == Test::AbstractThing }}.should be_true

        # The process will crash if this doesn't work.
        subject = Test::Subclass.new.as_abstract_thing
        subject.should be_a(Test::AbstractThing)
        String.new(subject.name).should eq("Hello")
      end
    end
  end
end
