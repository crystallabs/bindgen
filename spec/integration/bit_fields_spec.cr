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

      it "supports bit-fields in a union" do
        variant = Test::Funcs.variant_make
        variant.wide.should eq(-5)
        variant.low = 9u32
        variant.low.should eq(9u32)
        Test::Funcs.variant_sum(variant).should eq(9)
      end

      it "pads for zero-width bit-fields" do
        value = Test::Funcs.zero_width_make
        value.a.should eq(1u8)
        value.b.should eq(2u8)
        value.bits.should eq(5u32)
        value.d.should eq(7)
        value.e.should eq(3u8)
        value.bits = 6u32
        Test::Funcs.zero_width_sum(value).should eq(1 + 2 + 6 + 7 + 3)
        sizeof(Test::Binding::ZeroWidth).should eq(24)
        offsetof(Test::Binding::ZeroWidth, @_bits0).should eq(8)
        offsetof(Test::Binding::ZeroWidth, @e).should eq(20)
      end

      it "supports bit-fields of the size types" do
        sizes = Test::Funcs.sizes_make
        sizes.size.should eq(1000)
        sizes.delta.should eq(-100)
        sizes.delta = -5
        sizes.size = 2000
        Test::Funcs.sizes_sum(sizes).should eq(1995)
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
