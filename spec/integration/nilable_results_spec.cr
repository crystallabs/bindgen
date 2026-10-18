require "./spec_helper"

describe "nilable_results feature" do
  it "works" do
    build_and_run("nilable_results") do
      it "returns nil for a null pointer" do
        Test::Node.none.should be_nil
        Test::Node.new.link.should be_nil
        typeof(Test::Node.new.link).should eq(Test::Node?)
      end

      it "returns the wrapper for a pointer" do
        some = Test::Node.some
        some.should be_a(Test::Node)
        some.not_nil!.value.should eq(5)
        Test::Node.new.self.should be_a(Test::Node) # A reference, never nil
      end

      it "keeps nilable arguments" do
        Test::Node.new.value_of(nil).should eq(-1)
        Test::Node.new.value_of(Test::Node.some.not_nil!).should eq(5)
      end

      it "takes a nilable variable as argument" do
        maybe = Test::Node.some.as(Test::Node?) # A union, not nil nor the class
        Test::Node.new.value_of(maybe).should eq(5)
        Test::Node.new.value_of(nil.as(Test::Node?)).should eq(-1)
      end
    end
  end
end
