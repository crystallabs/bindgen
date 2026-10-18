require "./spec_helper"

describe "a basic C++ wrapper" do
  it "works" do
    build_and_run("basic") do
      context "core functionality" do
        it "supports static methods" do
          Test::AdderWrap.sum(4, 5).should eq(9)
        end

        it "supports member methods" do
          Test::AdderWrap.new(4).sum(5).should eq(9)
        end

        it "supports copy constructors" do
          original = Test::Copyable.new(1)
          copy = Test::Copyable.new(original)
          copy.value.should eq(2)
          copy.value = 5
          original.value.should eq(1)
        end

        it "supports assignment operators" do
          target = Test::Copyable.new(1)
          target.assign!(Test::Copyable.new(3)).value.should eq(13)
          target.value.should eq(13)
        end

        it "doesn't wrap constructors of undestructible classes" do
          Test::Undestructible.value.should eq(7)
          # Only `#initialize(unwrap)`
          {{ Test::Undestructible.methods.select(&.name.== "initialize").size }}.should eq(1)
        end

        it "supports conversion operators" do
          Test::Copyable.new(7).to_int.should eq(7)
          Test::Copyable.new(0).to_bool.should be_false
        end

        it "defaults a nullptr pointer argument to nil" do
          Test::Flags.new.flagged.should eq(0)
          flag = false
          Test::Flags.new.flagged(pointerof(flag)).should eq(1)
          flag.should be_true
        end

        it "names a deduced auto return type" do
          Test::Deduced.new.number.should eq(9)
          Test::Deduced.new.inner.v.should eq(4)
        end

        it "drops an operator Crystal can't name" do
          Test::Arrow.new.ok.should eq(1)
          Test::Arrow.new.responds_to?(:deref).should be_false
        end

        it "renames a parameter named like a keyword" do
          Test::Params.keep(2, 3).should eq(5)
        end

        it "skips a templated friend operator" do
          Test::Stream.new.count.should eq(0)
        end

        it "gives a value struct property methods" do
          pixel = Test::Pixel.new
          pixel.x = 3
          pixel.y = 4
          pixel.x.should eq(3)
          pixel.y.should eq(4)
          other = Test::Pixel2.new
          other.x = 7
          other.x.should eq(7)
        end

        it "prefixes a method named like a reserved Crystal method" do
          init = Test::Init.new
          init.check.should be_false
          init.cpp_initialize
          init.check.should be_true
        end

        it "converts the result of an operator as a whole" do
          (Test::Clock.new - Test::Clock.new).should eq(1500)
        end

        it "supports member operator overloading" do
          subject = Test::Ops.new

          (subject + 1).should eq(1)
          (subject - 2).should eq(4)
          (subject * 3).should eq(9)
          (subject / 4).should eq(16)
          (subject % 5).should eq(25)
          (subject & 6).should eq(36)
          (subject | 7).should eq(49)
          (subject ^ 8).should eq(64)
          (subject << 9).should eq(81)
          (subject >> 10).should eq(100)
          subject.and(11).should eq(121)
          subject.or(12).should eq(144)
          (subject == 13).should eq(169)
          (subject != 14).should eq(196)
          (subject < 15).should eq(225)
          (subject > 16).should eq(256)
          (subject <= 17).should eq(289)
          (subject >= 18).should eq(324)
          subject[19].should eq(361)

          subject.add!(1).should eq(101)
          subject.sub!(2).should eq(204)
          subject.mul!(3).should eq(309)
          subject.div!(4).should eq(416)
          subject.mod!(5).should eq(525)
          subject.bit_and!(6).should eq(636)
          subject.bit_or!(7).should eq(749)
          subject.bit_xor!(8).should eq(864)
          subject.lshift!(9).should eq(981)
          subject.rshift!(10).should eq(1100)

          (+subject).should eq(10001)
          (-subject).should eq(10002)
          subject.deref.should eq(10003)
          (~subject).should eq(10004)
          subject.not.should eq(10005)
          subject.succ!.should eq(10006)
          subject.pred!.should eq(10007)
          subject.post_succ!.should eq(10008)
          subject.post_pred!.should eq(10009)

          subject.call.should eq(20001)
          subject.call(0).should eq(20002)
          subject.call(0, 0).should eq(20003)
          subject.call(false).should eq(20004)
        end

        it "supports non-member operator overloading" do
          subject = Test::FreeOps.new

          (subject + 1).should eq(1)
          (subject - 2).should eq(4)
          (subject * 3).should eq(9)
          (subject / 4).should eq(16)
          (subject % 5).should eq(25)
          (subject & 6).should eq(36)
          (subject | 7).should eq(49)
          (subject ^ 8).should eq(64)
          (subject << 9).should eq(81)
          (subject >> 10).should eq(100)
          subject.and(11).should eq(121)
          subject.or(12).should eq(144)
          (subject == 13).should eq(169)
          (subject != 14).should eq(196)
          (subject < 15).should eq(225)
          (subject > 16).should eq(256)
          (subject <= 17).should eq(289)
          (subject >= 18).should eq(324)

          subject.add!(1).should eq(101)
          subject.sub!(2).should eq(204)
          subject.mul!(3).should eq(309)
          subject.div!(4).should eq(416)
          subject.mod!(5).should eq(525)
          subject.bit_and!(6).should eq(636)
          subject.bit_or!(7).should eq(749)
          subject.bit_xor!(8).should eq(864)
          subject.lshift!(9).should eq(981)
          subject.rshift!(10).should eq(1100)

          (+subject).should eq(10001)
          (-subject).should eq(10002)
          subject.deref.should eq(10003)
          (~subject).should eq(10004)
          subject.not.should eq(10005)
          subject.succ!.should eq(10006)
          subject.pred!.should eq(10007)
          subject.post_succ!.should eq(10008)
          subject.post_pred!.should eq(10009)
        end
      end

      context "argument-less default constructor" do
        it "is generated if class is default-constructible" do
          {{
            Test::ImplicitConstructor.methods.any? do |m|
              m.name == "initialize" && m.args.empty?
            end
          }}.should be_true
        end

        it "is omitted if class is not default-constructible" do
          {{
            Test::PrivateConstructor.methods.any? do |m|
              m.name == "initialize" && m.args.empty?
            end
          }}.should be_false
          {{
            Test::DeletedConstructor.methods.any? do |m|
              m.name == "initialize" && m.args.empty?
            end
          }}.should be_false
        end
      end

      context "crystal wrapper features" do
        it "adds `#initialize(unwrap: Binding::T*)`" do
          {{
            Test::AdderWrap.methods.any? do |m|
              m.name == "initialize" && \
                 m.args.size == 1 && \
                 m.args.any? do |a|
                  a.name.stringify == "unwrap"
                end
            end
          }}.should be_true
        end

        it "adds `#initialize(*, ...)` for aggregate types" do
          {{
            Test::Aggregate.methods.any? do |m|
              m.name == "initialize" && \
                 m.splat_index == 0 && \
                 m.args.map(&.name.stringify) == ["", "x", "y", "z"]
            end
          }}.should be_true
        end

        it "initializes aggregate types" do
          subject = Test::Aggregate.new(x: 4, y: 1.5, z: true)
          subject.x.should eq(4)
          subject.y.should eq(1.5)
          subject.z.should be_true
        end

        it "adds no aggregate constructor if a constructor is declared" do
          {{
            Test::DefaultedConstructor.methods.any? do |m|
              m.name == "initialize" && m.splat_index == 0
            end
          }}.should be_false

          Test::DefaultedConstructor.new.should be_a(Test::DefaultedConstructor)
        end

        it "initializes aggregate types which can't be moved" do
          subject = Test::NonMovableAggregate.new(x: 4, counter: 5)
          subject.x.should eq(4)
          subject.counter.should eq(5)
          subject.sum.should eq(9)
        end
      end

      context "method filtering" do
        methods = {{ Test::AdderWrap.methods.map(&.name.stringify) }}
        it "removes argument value type" do
          methods.includes?("ignoreByArgument").should be_false
        end
      end

      context "copy structure" do
        it "supports normal members" do
          Test::Binding::PlainStruct.new.x.should be_a(Int32)
          Test::Binding::PlainStruct.new.xp.should be_a(Pointer(Int32))
          Test::Binding::PlainStruct.new.vp.should be_a(Pointer(Void))
          Test::Binding::PlainStruct.new.vpp.should be_a(Pointer(Pointer(Void)))
        end

        it "supports array members" do
          Test::Binding::PlainStruct.new.y.should be_a(StaticArray(Int32, 4))
          Test::Binding::PlainStruct.new.yp.should be_a(StaticArray(Pointer(Int32), 6))
          Test::Binding::PlainStruct.new.z.should be_a(StaticArray(StaticArray(Int32, 16), 8))
        end
      end

      context "type decay matching" do
        it "supports specialized matching" do
          subject = Test::TypeConversion.new
          # `char *greet(const char *)` to `greet(String) : String`
          subject.greet("User").should eq("Hello User!")
        end

        it "supports base-type matching" do
          subject = Test::TypeConversion.new
          subject.next(5u8).should eq(6u8)
        end

        it "returns a void pointer" do
          subject = Test::TypeConversion.new
          subject.void_pointer.address.should eq(0x11223344)
        end

        it "passes a const void pointer as a Void*" do
          subject = Test::TypeConversion.new
          typeof(subject.const_void_pointer).should eq(Pointer(Void))
          subject.const_void_pointer.address.should eq(0x11223344)
          subject.address_of(subject.const_void_pointer).should eq(0x11223344)
        end

        it "evaluates code once in templates using it twice" do
          subject = Test::TypeConversion.new
          subject.counted.should eq(11 * 11)
          subject.counted_call_count.should eq(1)
          subject.take_counted(3).should eq((3 + 3) + (3 + 3))
        end
      end
    end
  end
end
