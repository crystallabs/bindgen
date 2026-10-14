require "./spec_helper"

describe "C-only functionality" do
  it "works" do
    build_and_run("c_only") do
      it "binds function with explicit extern C" do
        Test.one.should eq(1)
      end

      it "binds a function matched by several keys once" do
        {{ Test.has_constant?("Twice") }}.should be_false
      end

      it "binds function within extern C scope" do
        Test.two.should eq(2)
      end

      it "binds function in a namespace" do
        Test.five.should eq(5)
      end

      it "binds variadic function" do
        Test.sum(3, 4, 5, 6).should eq(4 + 5 + 6)
      end

      it "binds function class" do
        subject = Test::Class.new
        subject.three.should eq(3)
        Test::Class.four.should eq(4)
      end
    end
  end
end
