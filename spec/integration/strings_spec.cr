require "./spec_helper"

describe "std::string functionality" do
  it "works" do
    build_and_run("strings") do
      LONG_STRING = "A string that is too long for the small string optimization"

      class CountingStrings < Test::Strings
        getter calls = 0

        def virtual_name : String
          @calls += 1
          "A Crystal string which is also quite long, number #{@calls};"
        end
      end

      context "function result" do
        it "returns a string by value" do
          Test::Funcs.by_value.should eq(LONG_STRING)
        end

        it "returns a const string by value" do
          Test::Funcs.by_const_value.should eq("btrfs")
        end

        it "calls the function only once" do
          before = Test::Funcs.calls
          Test::Funcs.by_value
          (Test::Funcs.calls - before).should eq(1)
        end
      end

      context "method result" do
        it "returns a string by value" do
          subject = Test::Strings.new
          subject.by_value.should eq("btrfs")
          subject.long_by_value.should eq(LONG_STRING + "!")
        end

        it "returns a string by reference" do
          Test::Strings.new.by_reference.should eq(LONG_STRING)
        end

        it "returns a string by value from a static method" do
          Test::Strings.static_by_value.should eq(LONG_STRING + "?")
        end

        it "passes a string through" do
          subject = Test::Strings.new
          subject.echo("").should eq("")
          subject.echo("Hello").should eq("Hello")
          subject.echo(LONG_STRING * 100).should eq(LONG_STRING * 100)
          subject.echo("a\0b").should eq("a\0b")
        end

        it "calls the method only once" do
          subject = Test::Strings.new
          before = Test::Funcs.calls
          subject.by_value
          (Test::Funcs.calls - before).should eq(1)
        end
      end

      context "virtual method" do
        it "returns a string from C++" do
          Test::Strings.new.call_virtual_name.should eq("C++C++")
        end

        it "returns a string from Crystal, calling the method only once" do
          subject = CountingStrings.new
          subject.call_virtual_name.should eq(
            "A Crystal string which is also quite long, number 1;" \
            "A Crystal string which is also quite long, number 2;"
          )
          subject.calls.should eq(2)
        end
      end
    end
  end
end
