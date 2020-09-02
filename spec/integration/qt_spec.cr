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

      context "signal behaviour" do
        it "creates a on_X method" do
          subject = Test::SomeObject.new

          called = false
          subject.on_stuff_happened do
            called = true
          end

          called.should be_true
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

            # check that tag-less overload isn't defined on Crystal
            {{
              Test::SomeObject.methods.select do |method|
                method.name == "on_overloaded" && method.args.empty?
              end.size
            }}.should eq(0)
          end
        end

        context "private signals" do
          it "don't have an emission method" do
            {{ Test::SomeObject.methods.map(&.name.stringify) }}.includes?("private_signal").should be_false
          end

          it "have the connection method" do
            {{ Test::SomeObject.methods.map(&.name.stringify) }}.includes?("on_private_signal").should be_true
            {{ Test::SomeObject.methods.find(&.name.== "on_private_signal").args.size }}.should eq(0)
          end
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
