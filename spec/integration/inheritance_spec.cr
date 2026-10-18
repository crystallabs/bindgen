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
        Test::Subclass.new.const_overload.should eq(3)
      end

      it "supports nested classes with a wrapped base" do
        subject = Test::Outer::Inner.new
        subject.is_a?(Test::Base).should be_true
        subject.inner.should eq(12)
        subject.calc(3, 4).should eq(7)
      end

      it "doesn't inherit in Crystal from a base not at offset 0" do
        subject = Test::Polymorphic.new
        subject.is_a?(Test::NonPolymorphic).should be_false
        subject.read.should eq(11)
        subject.as_non_polymorphic.read.should eq(11)
      end

      it "doesn't wrap private overrides of methods of second base" do
        {{ Test::Subclass.has_method?("privately_overridden") }}.should be_false
        Test::Subclass.new.as_abstract_thing.privately_overridden.should eq(6)
      end

      it "gives the Impl class of an abstract subclass the inherited overloads" do
        made = Test::ScalerFactory.make
        made.should be_a(Test::AbstractScalerMiddleImpl)
        made.scaled(3).should eq(6) # The default argument's overload
        made.padded.should eq(2)    # A default Crystal can't express
        made.padded(3).should eq(3)
        made.scaled(3, 3).should eq(9)
        made.extra.should eq(7)
        Test::ConcreteScaler.new.scaled(2).should eq(4)
      end

      it "wraps a method re-exported by a using-declaration" do
        Test::Recursive.new.lock.should eq(7)
        Test::Recursive.new.responds_to?(:unlock).should be_false
      end

      it "casts down to an abstract class through its Impl class" do
        made = Test::ScalerFactory.make.as(Test::AbstractScaler)
        middle = made.to?(Test::AbstractScalerMiddle)
        middle.should be_a(Test::AbstractScalerMiddleImpl)
        middle.not_nil!.extra.should eq(7)
      end

      it "reaches a privately overridden method through its base" do
        Test::Circle.new.sides.should eq(0)
        Test::Circle.new.corners.should eq(0)
        round = Test::Shapes.round
        round.should be_a(Test::AbstractRoundImpl)
        round.sides.should eq(0)
        round.area.should eq(28)
      end

      it "adds shadow-impl class for abstract classes" do
        {{ Test::AbstractThingImpl.superclass == Test::AbstractThing }}.should be_true

        # The process will crash if this doesn't work.
        subject = Test::Subclass.new.as_abstract_thing
        subject.should be_a(Test::AbstractThing)
        String.new(subject.name).should eq("Hello")
      end

      context "#to?" do
        it "casts down to a sub-class" do
          dog = Test::Animal.create(0).to?(Test::Dog)
          dog.should be_a(Test::Dog)
          dog.as(Test::Dog).fetch.should eq(1)

          puppy = Test::Animal.create(1).to?(Test::Puppy)
          puppy.should be_a(Test::Puppy)
          puppy.as(Test::Puppy).fetch.should eq(2)
        end

        it "casts down through a Crystal superclass" do
          puppy = Test::Animal.create(1).to?(Test::Dog).as(Test::Dog).to?(Test::Puppy)
          puppy.as(Test::Puppy).fetch.should eq(2)
        end

        it "returns nil if the instance isn't of that type" do
          Test::Animal.create(0).to?(Test::Puppy).should be_nil
          Test::Animal.create(0).to?(Test::Hamster).should be_nil
          Test::Animal.create(2).to?(Test::Dog).should be_nil
          Test::Base.new.to?(Test::Subclass).should be_nil
        end

        it "wraps the same object" do
          subject = Test::Subclass.new
          subject.belong_to_us.to?(Test::Subclass).as(Test::Subclass).to_unsafe.should eq(subject.to_unsafe)
          subject.belong_to_us.to?(Test::Subclass).as(Test::Subclass).calc(4, 5).should eq(20)
        end

        it "casts down from a secondary base" do
          hamster = Test::Animal.create(2).to?(Test::Hamster).as(Test::Hamster)
          pet = hamster.to?(Test::Pet)
          pet.should be_a(Test::Pet)
          pet.owner.should eq(3)

          again = pet.to?(Test::Hamster).as(Test::Hamster)
          again.to_unsafe.should eq(hamster.to_unsafe)
          again.wheel.should eq(5)

          thing = Test::Subclass.new.as_abstract_thing
          String.new(thing.to?(Test::Subclass).as(Test::Subclass).name).should eq("Hello")
        end

        it "returns self when casting to the own type" do
          dog = Test::Dog.new
          dog.to?(Test::Dog).should be(dog)
          typeof(dog.to?(Test::Dog)).should eq(Test::Dog)
        end

        it "returns self when casting to a Crystal superclass" do
          puppy = Test::Puppy.new
          puppy.to?(Test::Dog).should be(puppy)
          puppy.to?(Test::Animal).should be(puppy)

          subject = Test::Subclass.new
          subject.to?(Test::Base).should be(subject)
        end

        it "casts up to a secondary base" do
          thing = Test::Subclass.new.to?(Test::AbstractThing)
          thing.should be_a(Test::AbstractThing)
          String.new(thing.name).should eq("Hello")
        end

        it "returns a nilable downcast result" do
          typeof(Test::Dog.new.to?(Test::Puppy)).should eq(Test::Puppy?)
          typeof(Test::Pet.new.to?(Test::Hamster)).should eq(Test::Hamster?)
        end

        it "isn't added to non-polymorphic classes" do
          {{ Test::Super1.has_method?("to?") }}.should be_false
          {{ Test::Module::Derived1.has_method?("to?") }}.should be_false
        end
      end

      context "covariant return types" do
        it "wraps the override, and not the base method again" do
          {{ Test::Square.methods.select(&.name.== "clone").size }}.should eq(1)
          clone = Test::Square.new.clone
          clone.should be_a(Test::Square)
          clone.as(Test::Square).sides.should eq(4)
        end
      end
    end
  end
end
