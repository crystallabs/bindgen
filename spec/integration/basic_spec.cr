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
      end
    end
  end
end
