require "./spec_helper"

describe "out arguments" do
  it "works" do
    build_and_run("out_arguments") do
      class CrystalTransformer < Test::Transformer
        def transform(text : String, count : Int32) : {Int32, String, Int32}
          {7, "Crystal #{text}", count * 2}
        end

        def describe : String
          "crystal"
        end
      end

      class SuperTransformer < Test::Transformer
        def transform(text, count)
          result, text, count = super
          {result + 1, text + "+", count + 1}
        end
      end

      class SuperclassTransformer < Test::Transformer
        def transform(text, count)
          result, text, count = superclass.transform(text, count)
          {result + 2, text + "~", count + 2}
        end
      end

      class RaisingTransformer < Test::Transformer
        def transform(text, count) : {Int32, String, Int32}
          raise "nope"
        end
      end

      class LowerFormatter < Test::AbstractFormatter
        def format(text : String) : String
          text.downcase
        end

        def prefix : {String, String}
          {"P", "S"}
        end
      end

      context "wrapper" do
        it "returns an in/out reference alone from a void method" do
          Test::Outs.new.shout("hi").should eq("hi!")
        end

        it "returns an out pointer alone from a void method" do
          Test::Outs.new.name.should eq("outs")
        end

        it "returns the result first, then the in/out values" do
          Test::Outs.new.validate("x", 1).should eq({7, "valid x", 2})
        end

        it "passes a local for an out pointer defaulting to nullptr" do
          Test::Outs.new.info.should eq({true, "localhost", 42})
        end

        it "returns a tuple of several out pointers from a void method" do
          Test::Outs.new.split("a,b").should eq({"a", "b"})
          Test::Outs.new.split("a").should eq({"a", ""})
        end

        it "keeps the variant with the out pointer over the one without" do
          subject = Test::Outs.new
          subject.pick(1).should eq("picked 1")
          subject.pick(2, Test::Flavor.new(4)).should eq({"picked 2", "40"})
          subject.pick(3, Test::Flavor.new(4), 5).should eq({"picked 3", "45"})
        end

        it "drops other indirections to converted types" do
          subject = Test::Outs.new
          subject.responds_to?(:dropped_pointer_to_pointer).should be_false
          subject.responds_to?(:dropped_const_pointer).should be_false
          subject.responds_to?(:dropped_reference_to_pointer).should be_false
        end

        it "drops a constructor taking a pointer to a converted type" do
          Test::Keeper.new.value.should eq(1)
          # The default, copy and `unwrap:` constructors, but no second
          # argument-less one for `Keeper(std::string *)`.
          {{ Test::Keeper.methods.select(&.name.==("initialize")).map(&.args.size) }}.sort.should eq([0, 1, 1])
        end
      end

      context "virtual override" do
        it "calls the C++ method through the wrapper" do
          Test::Transformer.new.transform("x", 1).should eq({1, "C++ x", 11})
          Test::Transformer.new.run_transform("x", 1).should eq("C++ x/11/1")
          Test::Transformer.new.run_describe.should eq("base")
        end

        it "writes the override's tuple back into the C++ references" do
          subject = CrystalTransformer.new
          subject.run_transform("x", 1).should eq("Crystal x/2/7")
          subject.transform("x", 1).should eq({7, "Crystal x", 2})
        end

        it "writes the override's value through an out pointer" do
          subject = CrystalTransformer.new
          subject.run_describe.should eq("crystal")
          subject.describe.should eq("crystal")
          subject.describe_nowhere
        end

        it "calls the C++ method from a subclass not overriding it" do
          SuperTransformer.new.run_describe.should eq("base")
          SuperTransformer.new.describe.should eq("base")
        end

        it "supports super and superclass in the override" do
          SuperTransformer.new.run_transform("x", 1).should eq("C++ x+/12/2")
          SuperclassTransformer.new.run_transform("x", 1).should eq("C++ x~/13/3")
        end

        it "leaves the arguments alone if the override raises" do
          caught = [] of ::Exception
          default = Test::BindgenHelper.on_exception
          Test::BindgenHelper.on_exception = ->(e : ::Exception) { caught << e; nil }

          begin
            RaisingTransformer.new.run_transform("x", 1).should eq("x/1/0")
          ensure
            Test::BindgenHelper.on_exception = default
          end

          caught.map(&.message).should eq(["nope"])
        end
      end

      context "pure virtual" do
        it "is implemented in Crystal" do
          subject = LowerFormatter.new
          subject.run("ABC").should eq("abc")
          subject.run_prefix.should eq("PS")
          Test::Formatters.run(subject, "ABC").should eq("abc")
        end

        it "is called through the Impl class" do
          subject = Test::Formatters.upper
          subject.run("abc").should eq("ABC")
          subject.format("abc").should eq("ABC")
          subject.prefix.should eq({"p", "s"})
        end
      end
    end
  end
end
