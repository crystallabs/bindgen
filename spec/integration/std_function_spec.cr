require "./spec_helper"

describe "std::function arguments" do
  it "works" do
    build_and_run("std_function") do
      # Counts its collected instances.
      class Payload
        class_property collected = 0

        def finalize
          Payload.collected += 1
        end
      end

      # Overwrites the stack below its caller, so pointers to dead objects
      # left in it don't keep them alive.
      @[NoInline]
      def scrub_stack
        buffer = uninitialized UInt8[65536]
        buffer.to_slice.fill(0)
      end

      # Collects garbage, and allocates objects meanwhile, so the memory of
      # collected objects is reused.
      def collect_garbage
        10.times do
          scrub_stack
          GC.collect
          10.times { Pointer(UInt8).malloc(16) }
        end
        GC.collect
      end

      # Gives *button* a block capturing a `Payload`, in a frame of its own.
      @[NoInline]
      def connect(button, counter : Pointer(Int32)) : Nil
        payload = Payload.new
        button.on_click { counter.value += 1 if payload }
      end

      context "block arguments" do
        it "are called with converted arguments and results" do
          button = Test::Button.new
          seen = [] of String
          button.each(3) do |index, name|
            seen << "#{name}#{index}"
            index * 2
          end.should eq(6)
          seen.should eq(["item0", "item1", "item2"])

          button.transform(->(s : String) { s.upcase }, "abc").should eq("ABC")
        end

        it "are taken as a Proc when not last" do
          button = Test::Button.new
          button.set_filter(->(value : Int32) { value.even? }, 10)
          button.passes(12).should be_true
          button.passes(13).should be_false
          button.passes(2).should be_false
        end

        it "are called through a virtual method" do
          Test::Button.new.visit { |value| value * 2 }.should eq(42)
          {{ Test::Button.methods.map(&.name.stringify) }}.should_not contain("handler")
          {{ Test::Button.methods.map(&.name.stringify) }}.should_not contain("raw")
        end

        it "stay alive while C++ keeps the function" do
          button = Test::Button.new
          counter = 0
          connect(button, pointerof(counter))

          collected = Payload.collected
          5.times { collect_garbage }
          Payload.collected.should eq(collected)
          button.trigger.should be_true
          counter.should eq(1)

          # Dropped by C++, the closure is collected.
          button.release
          50.times do
            break if Payload.collected > collected
            collect_garbage
          end
          Payload.collected.should eq(collected + 1)
          button.trigger.should be_false
        end
      end
    end
  end
end
