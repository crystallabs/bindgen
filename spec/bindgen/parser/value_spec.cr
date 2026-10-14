require "../../spec_helper"

private def parse_and_read(document)
  pull = JSON::PullParser.new(document)
  Bindgen::Parser::ValueConverter.from_json(pull)
end

describe Bindgen::Parser::ValueConverter do
  describe ".from_json" do
    it "reads a null" do
      parse_and_read("null").should be_nil
    end

    it "reads a UInt64" do
      parse_and_read("0").should be_a(UInt64)
      parse_and_read("0").should eq(0u64)
      parse_and_read("1").should eq(1u64)
      parse_and_read("9223372036854775808").should eq(0x80_00_00_00_00_00_00_00u64)
    end

    it "reads a Int64" do
      parse_and_read("-1").should be_a(Int64)
      parse_and_read("-1").should eq(-1i64)
    end

    it "reads a Float64" do
      parse_and_read("0.0").should eq(0.0)
      parse_and_read("1.0").should eq(1.0)
      parse_and_read("-1.0").should eq(-1.0)
    end

    it "reads a Bool" do
      parse_and_read("true").should be_true
      parse_and_read("false").should be_false
    end

    it "reads a String" do
      parse_and_read(%<"Hello">).should eq("Hello")
    end

    it "raises an error otherwise" do
      expect_raises(Exception, /unexpected json kind/i) do
        parse_and_read("[]")
      end
    end
  end
end
