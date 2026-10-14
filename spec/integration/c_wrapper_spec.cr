require "./spec_helper"

describe "C-specific functionality" do
  it "works" do
    build_and_run("c_wrapper") do
      context "constants" do
        it "maps them into the target module" do
          Test::ONE.should eq(1)
          Test::TWO.should eq(2)
          Test::THREE.should eq("Three")
        end

        it "maps them into a new module" do
          Test::Foo::A.should eq("A")
          Test::Foo::B.should eq("B")
          Test::Foo::C.should eq("C")
        end

        it "evaluates complex macros" do
          Test::Complex::A.should eq(3)
          Test::Complex::B.should eq(5)
          Test::Complex::C.should eq("FooBar")
        end

        it "chooses the correct Crystal type" do
          Test::Value::INT32.should be_a(Int32)
          Test::Value::INT32.should eq(1)
          Test::Value::INT64.should be_a(Int64)
          Test::Value::INT64.should eq(1)
          Test::Value::UINT32.should be_a(UInt32)
          Test::Value::UINT32.should eq(1)
          Test::Value::NEGATIVE_INT32.should be_a(Int32)
          Test::Value::NEGATIVE_INT32.should eq(-123)
          Test::Value::NEGATIVE_INT64.should be_a(Int64)
          Test::Value::NEGATIVE_INT64.should eq(-123)
          Test::Value::LARGE_UINT64.should be_a(UInt64)
          Test::Value::LARGE_UINT64.should eq(9223372036854775808_u64)
          Test::Value::LARGE_INT64.should be_a(Int64)
          Test::Value::LARGE_INT64.should eq(9223372036854775807)
          Test::Value::TRUE.should be_a(Bool)
          Test::Value::TRUE.should eq(true)
          Test::Value::FALSE.should be_a(Bool)
          Test::Value::FALSE.should eq(false)
          Test::Value::FLOAT.should be_a(Float64)
          Test::Value::FLOAT.should eq(3.5)
        end

        it "allows to force the type of constants" do
          Test::Forced::A.should be_a(Int32)
          Test::Forced::B.should be_a(Int32)
          Test::Forced::C.should be_a(Int32)
          Test::Forced::D.should be_a(Int32)
          Test::Forced::E.should be_a(Int32)

          Test::Forced::A.should eq(1)
          Test::Forced::B.should eq(2)
          Test::Forced::C.should eq(3)
          Test::Forced::D.should eq(4)
          Test::Forced::E.should eq(5)
        end
      end

      context "enums" do
        it "maps an enum type" do
          {{ Test::Things.ancestors.includes?(Enum) }}.should be_true
          Test::Things::ThingOne.value.should eq(1)
          Test::Things::ThingTwo.value.should eq(2)
          Test::Things::ThingThree.value.should eq(3)
        end

        it "defaults to Int32" do
          typeof(Test::Things::ThingOne.value).should eq(Int32)
        end

        it "maps a flags enum type" do
          {{ Test::Foo::Bar.ancestors.includes?(Enum) }}.should be_true
          Test::Foo::Bar::One.value.should eq(1)
          Test::Foo::Bar::Two.value.should eq(2)
          Test::Foo::Bar::Four.value.should eq(4)

          Test::Foo::Bar::None.value.should eq(0)
          Test::Foo::Bar::All.value.should eq(1 | 2 | 4)
        end

        it "uses the configured base type" do
          typeof(Test::Foo::Bar::One.value).should eq(UInt32)
        end
      end

      context "simple functions" do
        it "maps short-hand" do
          Test::Funcs.one.should eq(1)
        end

        it "maps through full name" do
          Test::Funcs.two.should eq(2)
        end

        it "maps short-hand with one capture group" do
          Test::Funcs::Thr.ee.should eq(3)
        end

        it "maps with one capture group" do
          Test::Funcs.four.should eq(4)
        end
      end

      context "multiple function matches" do
        it "maps with short-hand" do
          Test::Funcs::Calc.add(4, 3).should eq(7)
          Test::Funcs::Calc.sub(4, 3).should eq(1)
        end
      end

      context "functions with individual nesting" do
        it "maps them accordingly" do
          Test::Funcs::Increment.one(5).should eq(6)
          Test::Funcs::Decrement.one(5).should eq(4)
        end
      end

      context "functions in a namespace" do
        it "maps by qualified name" do
          Test::Storage::Read.one.should eq(1)
          Test::Storage::Read.two.should eq(2)
        end

        it "maps by qualified name in a nested namespace" do
          Test::Storage::Deep.read_three.should eq(3)
        end

        it "maps by bare name" do
          Test::Storage::Write.one.should eq(10)
        end

        it "prefers the qualified name" do
          Test::Storage::Storage.get.should eq(20)
        end
      end

      context "functions with crystalized names" do
        it "defaults to false" do
          Test::DontCrystalize.set_foo(5)
          Test::DontCrystalize.get_foo.should eq(5)
          Test::DontCrystalize.is_foo_zero.should be_false

          Test::DontCrystalize.set_foo(0)
          Test::DontCrystalize.get_foo.should eq(0)
          Test::DontCrystalize.is_foo_zero.should be_true
        end

        it "can be explicitly enabled" do
          Test::Crystalize.foo = 5
          Test::Crystalize.foo.should eq(5)
          Test::Crystalize.foo_zero?.should be_false

          Test::Crystalize.foo = 0
          Test::Crystalize.foo.should eq(0)
          Test::Crystalize.foo_zero?.should be_true
        end
      end

      context "function classes" do
        it "wraps functions as methods" do
          instance_methods = {{ Test::Buffer.methods.map(&.name.stringify) }}
          static_methods = {{ Test::Buffer.class.methods.map(&.name.stringify) }}

          # Constructors
          ctor_arguments = {{
                             Test::Buffer.methods.select(&.name.== "initialize").map do |meth|
                               (meth.args.map(&.name.stringify).stringify + " of String").id
                             end
                           }}
          ctor_arguments.includes?([] of String).should be_true # Default one
          ctor_arguments.includes?(["string"]).should be_true   # One with arguments

          # Member methods
          instance_methods.includes?("size").should be_true
          instance_methods.includes?("size=").should be_true
          instance_methods.includes?("empty?").should be_true
          instance_methods.includes?("string").should be_true
          instance_methods.includes?("append").should be_true

          # Destructor
          instance_methods.includes?("finalize").should be_true

          # Static method detection
          static_methods.includes?("version").should be_true
        end

        it "can call a static method" do
          Test::Buffer.version.should eq(123)
        end

        it "can interact with an instance" do
          buffer = Test::Buffer.new("Hello".to_unsafe)
          buffer.append ", ".to_unsafe
          buffer.append "Crystal!".to_unsafe

          string = String.new(buffer.string)
          string.should eq("Hello, Crystal!")
          buffer.size.should eq(string.size)
        end

        it "does normal Crystal method name rewriting" do
          buffer = Test::Buffer.new
          buffer.empty?.should be_true # Question getter
          buffer.size = 32             # Setter
          buffer.size.should eq(32)    # Getter
        end
      end

      context "function class of functions in a namespace" do
        it "maps constructor, members and static methods" do
          counter = Test::Counter.new
          counter.add(4)
          counter.add(3)
          counter.value.should eq(7)
          Test::Counter.limit.should eq(99)
        end

        it "doesn't map the destructor as method" do
          {{ Test::Counter.has_method?("free") }}.should be_false
          {{ Test::Counter.has_method?("finalize") }}.should be_true
        end
      end

      context "function class without crystalized names" do
        it "leaves the names alone" do
          instance_methods = {{ Test::MyInt.methods.map(&.name.stringify) }}

          instance_methods.includes?("set_value").should be_true
          instance_methods.includes?("get_value").should be_true
          instance_methods.includes?("is_zero").should be_true
        end

        it "can interact with this class" do
          int = Test::MyInt.new

          int.is_zero.should be_true
          int.get_value.should eq(0)
          int.set_value(4)
          int.is_zero.should be_false
          int.get_value.should eq(4)
        end
      end
    end
  end
end
