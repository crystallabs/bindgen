require "./spec_helper"

describe "bit-fields of copied structures" do
  it "works" do
    build_and_run("bit_fields") do
      it "reads bit-fields written by C++" do
        flags = Test::Funcs.flags_make
        flags.narrow.should eq(5u32)
        flags.wide.should eq(-1000)
        flags.on.should be_true
        flags.tiny.should eq(-3i8)
        flags.next.should eq(17u32)
        flags.value.should eq(99)
        flags.big.should eq(-100_000_000_000i64)
        flags.negative.should eq(-2i64)
      end

      it "writes bit-fields read by C++" do
        flags = Test::Binding::Flags.new
        flags.narrow = 6u32
        flags.wide = -7
        flags.on = true
        flags.tiny = 2i8
        flags.next = 31u32
        flags.value = 100
        flags.big = -5i64
        flags.negative = 3i64
        Test::Funcs.flags_sum(flags).should eq(6 - 7 + 1 + 2 + 31 + 100 - 5 + 3)
      end

      it "keeps the other bit-fields, and truncates the value" do
        flags = Test::Funcs.flags_make
        (flags.narrow = 9u32).should eq(9u32)
        flags.narrow.should eq(1u32)
        flags.wide.should eq(-1000)
        flags.on.should be_true
        flags.tiny.should eq(-3i8)
      end

      it "writes through a pointer" do
        pointer = Pointer(Test::Binding::Flags).malloc(1)
        pointer.value.wide = 42
        pointer.value.wide.should eq(42)
      end

      it "has no setter for a constant bit-field" do
        constants = Test::Funcs.constants_make
        constants.fixed.should eq(9u32)
        constants.free.should eq(3u32)
        {{ Test::Binding::Constants.has_method?("fixed=") }}.should be_false
      end

      it "supports a structure hosted by a wrapper class" do
        hosted = Test::Funcs.hosted_make
        hosted.should be_a(Test::Hosted)
        hosted.low.should eq(7u32)
        hosted.high = 3u32
        hosted.high.should eq(3u32)
        hosted.low.should eq(7u32)
      end
    end

    # The methods call C++ accessors.
    output = File.read("#{__DIR__}/tmp/bit_fields.cr")
    output.should contain("fun bg_Flags_narrow_BITFIELD_GET_(")
    output.should contain("Binding.bg_Flags_narrow_BITFIELD_GET_(pointerof(@_bits0).as(Binding::Flags*))")
    output.should match(/# Three bits\.\n\s+def narrow : UInt32/)
  end
end
