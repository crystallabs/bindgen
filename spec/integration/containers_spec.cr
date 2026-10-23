require "./spec_helper"

describe "container instantiation feature" do
  it "works" do
    build_and_run("containers") do
      FloatMatrix = Test::Std::Vector.of(Test::Std::Vector(Float64))

      context "container of an ignored type" do
        it "isn't instantiated" do
          Test::Containers.new.responds_to?(:secrets).should be_false
        end
      end

      context "optional" do
        it "converts to and from a nilable" do
          subject = Test::Containers.new
          subject.maybe_int(true).should eq(42)
          subject.maybe_int(false).should be_nil
          typeof(subject.maybe_int(true)).should eq(Int32?)
          subject.maybe_string(true).should eq("some")
          subject.maybe_string(false).should be_nil
          subject.maybe_point(true).try(&.x).should eq(3)
          subject.maybe_point(false).should be_nil
          subject.unwrap_int(7).should eq(7)
          subject.unwrap_int(nil).should eq(-1)
          subject.greet("you").should eq("hello you")
          subject.greet(nil).should eq("hello nobody")
        end

        it "wraps an optional directly" do
          optional = Test::Std::Optional.of(Int32).from(5)
          optional.has_value?.should be_true
          optional.to_nilable.should eq(5)
          Test::Std::Optional.of(Int32).from(nil).to_nilable.should be_nil
          Test::Containers.new.unwrap_int(optional.to_nilable).should eq(5)
        end
      end

      context "pair" do
        it "converts to and from tuples" do
          Test::Containers.new.entry.should eq({"one", 1})
          Test::Containers.new.sum({2, 3}).should eq(5)
          Test::Containers.new.entries.to_a.should eq([{"a", 1}, {"b", 2}])
          Test::Containers.new.weights.to_a.should eq([{0.5, 1}, {1.5, 2}])
          pair = Test::Std::Pair.of(String, Int32).from({"x", 4})
          pair.first.should eq("x")
          pair.to_tuple.should eq({"x", 4})
        end

        it "looks through an alias template" do
          Test::Containers.new.aliased_entry.should eq({"two", 2})
          Test::Containers.new.aliased_weights.to_a.should eq([{2.5, 3}])
        end
      end

      context "sequential container" do
        it "works with explicitly instantiated container" do
          Test::Containers.new.integers.to_a.should eq([1, 2, 3])
        end

        it "works with auto instantiated container (result)" do
          Test::Containers.new.strings.to_a.should eq(["One", "Two", "Three"])
        end

        it "works with auto instantiated container (argument)" do
          list = [1.5, 2.5]
          Test::Containers.new.sum(list).should eq(4.0)
          Test::Containers.new.sum(Test::Std::Vector.of(Float64).from(list)).should eq(4.0)

          list = {3.5, 4.5}
          Test::Containers.new.sum(list).should eq(8.0)
          Test::Containers.new.sum(Test::Std::Vector.of(Float64).from(list)).should eq(8.0)
        end

        it "works with auto instantiated container (aliased container)" do
          Test::Containers.new.chars.to_a.should eq([1u8, 4u8, 9u8])
        end

        it "works with auto instantiated container (aliased element)" do
          Test::Containers.new.palette.to_a.should eq([0xFF0000u32, 0x00FF00u32, 0x0000FFu32])
          Test::Containers.new.brightest([1u32, 3u32, 2u32]).should eq(3u32)
          Test::Containers.new.palettes.map(&.to_a).should eq([[0xFF0000u32], [0x00FF00u32, 0x0000FFu32]])
        end

        it "instantiates a container of an aliased element only once" do
          # `std::vector<rgb>` and `std::vector<unsigned int>` are both used and
          # both configured, and are the same type.  There must be as many
          # wrappers of it as of `std::vector<int>`, which is one per standard
          # library namespace.
          wrappers = {{ Test.constants.map(&.stringify).select(&.starts_with?("Container_")) }}
          wrappers.count(&.includes?("rgb")).should eq(0)
          wrappers.count(&.ends_with?("vector_unsigned_int_")).should eq(wrappers.count(&.ends_with?("vector_int_")))

          Test::Containers.new.palette.class.should eq(Test::Containers.new.numbers.class)
          Test::Containers.new.numbers.to_a.should eq([1u32, 2u32, 3u32])
          Test::Containers.new.brightest(Test::Std::Vector.of(UInt32).from([4u32, 5u32])).should eq(5u32)
        end

        it "works with nested containers" do
          Test::Containers.new.grid.map(&.to_a).should eq([[1, 4], [9, 16]])

          mat = FloatMatrix{
            [1.2, 3.4],
            [5.6, 7.8],
          }
          Test::Containers.new.transpose(mat).map(&.to_a).should eq([[1.2, 5.6], [3.4, 7.8]])
        end
      end

      context "associative container" do
        it "works with auto instantiated container (result)" do
          names = Test::Containers.new.number_names
          names.should be_a(Test::Std::Map(Int32, String))
          names.size.should eq(3)
          names[2].should eq("Two")
          names[4]?.should be_nil
          expect_raises(KeyError) { names[4] }
          names.has_key?(1).should be_true
          names.has_key?(4).should be_false
          names.keys.should eq([1, 2, 3])
          names.values.should eq(["One", "Two", "Three"])
          names.to_h.should eq({1 => "One", 2 => "Two", 3 => "Three"})
          names.to_a.should eq([{1, "One"}, {2, "Two"}, {3, "Three"}])
          names.fetch(5, "Five").should eq("Five")
        end

        it "changes the container" do
          names = Test::Containers.new.number_names
          names[2] = "Zwei"
          names[4] = "Vier"
          names.to_h.should eq({1 => "One", 2 => "Zwei", 3 => "Three", 4 => "Vier"})

          names.delete(1).should eq("One")
          names.delete(1).should be_nil
          names.delete(1) { "Gone" }.should eq("Gone")
          names.keys.should eq([2, 3, 4])
        end

        it "allows changing the container while iterating" do
          names = Test::Containers.new.number_names

          seen = [] of Int32
          names.each do |key, _|
            seen << key
            names.delete(key + 1)
            names[key + 10] = "More"
          end

          # Iteration goes over the entries as they were when it started.
          seen.should eq([1, 2, 3])
          names.keys.should eq([1, 11, 12, 13])
        end

        it "works with auto instantiated container (argument)" do
          lengths = Test::Containers.new.word_lengths(["a", "bcd", "ef"])
          lengths.should be_a(Test::Std::UnorderedMap(String, Int32))
          lengths.to_h.should eq({"a" => 1, "bcd" => 3, "ef" => 2})
          Test::Containers.new.sum_values(lengths).should eq(6)

          Test::Containers.new.sum_values({"x" => 4, "y" => 5}).should eq(9)
          map = Test::Std::UnorderedMap.of(String, Int32).from({"z" => 7})
          map["z"].should eq(7)
          Test::Containers.new.sum_values(map).should eq(7)
        end

        it "works with aliased containers" do
          book = Test::Containers.new.phonebook_entries
          book.class.should eq(Test::Std::Map.of(String, Int32))
          book.to_h.should eq({"Alice" => 123, "Bob" => 456})
          book.to_s.should eq(%({"Alice" => 123, "Bob" => 456}))
        end

        it "works with nested containers" do
          multiples = Test::Containers.new.multiples(2)
          multiples[2].to_a.should eq([2, 4, 6])
          multiples.map { |k, v| {k, v.to_a} }.should eq([{1, [1, 2, 3]}, {2, [2, 4, 6]}])

          multiples[3] = [3, 6]
          Test::Containers.new.sum_all(multiples).should eq(6 + 12 + 9)
          Test::Containers.new.sum_all({5 => [5], 6 => [6, 6]}).should eq(17)
        end

        it "works with wrapped classes" do
          points = Test::Points.new.named
          points["unit"].y.should eq(1)
          points.keys.should eq(["origin", "unit"])
          points.values.map(&.x).should eq([0, 1])

          points["far"] = Test::Point.new(5, 6)
          points["unit"] = Test::Point.new(2, 2)
          Test::Points.new.sum_x(points).should eq(7)
          Test::Points.new.sum_x({"a" => Test::Point.new(3, 0)}).should eq(3)
        end

        it "works with configured method names" do
          roots = Test::QtStyle.new.square_roots
          roots.to_h.should eq({4 => 2.0, 9 => 3.0})
          roots[9].should eq(3.0)
          roots[16] = 4.0
          roots[4] = -2.0
          roots.delete(9).should eq(3.0)
          roots.has_key?(9).should be_false
          roots.to_h.should eq({4 => -2.0, 16 => 4.0})
        end
      end
    end
  end
end
