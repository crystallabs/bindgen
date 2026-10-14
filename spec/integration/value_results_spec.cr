require "./spec_helper"

describe "classes returned by value" do
  it "works" do
    build_and_run("value_results") do
      COUNT = 10_000

      it "returns the value" do
        Test::Tracked.make(5).value.should eq(5)
        Test::Tracked.make(5).twice.value.should eq(10)
        Test::Funcs.make(7).value.should eq(7)
      end

      it "returns a polymorphic value" do
        subject = Test::Polymorphic.make(6)
        subject.value.should eq(6)
        subject.which.should eq(3)
      end

      it "returns a trivially destructible value" do
        Test::Trivial.make(8).value.should eq(8)
      end

      # The GC is conservative, some of the instances may survive.
      it "runs the destructor of a static method's result" do
        before = Test::Tracked.alive
        COUNT.times { |i| Test::Tracked.make(i) }

        GC.collect
        (Test::Tracked.alive - before).should be < COUNT // 2
      end

      it "runs the destructor of a member method's result" do
        subject = Test::Tracked.new(1)
        before = Test::Tracked.alive
        COUNT.times { subject.twice }

        GC.collect
        (Test::Tracked.alive - before).should be < COUNT // 2
      end

      it "runs the destructor of a function's result" do
        before = Test::Tracked.alive
        COUNT.times { |i| Test::Funcs.make(i) }

        GC.collect
        (Test::Tracked.alive - before).should be < COUNT // 2
      end

      it "runs the destructor of a polymorphic result" do
        before = Test::Polymorphic.alive
        COUNT.times { |i| Test::Polymorphic.make(i) }

        GC.collect
        (Test::Polymorphic.alive - before).should be < COUNT // 2
      end
    end
  end
end
