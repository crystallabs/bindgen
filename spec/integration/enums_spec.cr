require "./spec_helper"

describe "enumeration types functionality" do
  it "works" do
    build_and_run("enums") do
      # See also ../spec/bindgen/processor/enums_spec.cr

      private def enum_type(enumeration : T.class) forall T
        typeof(T.values.first.value)
      end

      context "core functionality" do
        it "supports top-level enums" do
          Test::TopLevel.names.should eq(%w[A B CC])
          Test::TopLevel.values.map(&.to_i).should eq([0, 0, -1])
          enum_type(Test::TopLevel).should eq(Int32)
        end

        it "supports namespaced enums" do
          Test::NS1::InnerEnum::X.value.should eq(0)
          Test::NS1::NS2::InnerEnum2::X.value.should eq(0)
        end

        it "supports enums with explicit types" do
          Test::U8Enum.names.should eq(%w[D E])
          Test::U8Enum.values.map(&.to_i).should eq([0, 255])
          enum_type(Test::U8Enum).should eq(UInt8)
        end
      end

      context "Qt-specific functionality" do
        it "recognizes `QFlags<T>`" do
          {{ Test::Flags.annotation(Flags) ? true : false }}.should be_true
          Test::Flags.names.should eq(%w[P Q R])
          Test::Flags.values.map(&.to_i).should eq([1, 4, 12])
          Test::Flags::None.value.should eq(0)
          Test::Flags::All.value.should eq(13)
        end

        it "recognizes an uninstantiated `QFlags<T>` of an `enum class`" do
          {{ Test::ScopedFlags.annotation(Flags) ? true : false }}.should be_true
          Test::ScopedFlags.names.should eq(%w[S T])
          Test::ScopedFlags.values.map(&.to_i).should eq([1, 2])
        end
      end

      context "nested anonymous enums" do
        it "writes enum values to the enclosing scope as constants" do
          Test::Nested::X.should eq(10)
          Test::Nested::X.should be_a(UInt32)
          Test::Nested::Y.should eq(20)
          Test::Nested::Y.should be_a(UInt32)

          Test::MyRenamed::Z.should eq(30)
          {{ Test.has_constant?("Renamed") }}.should be_false
        end
      end
    end
  end
end
