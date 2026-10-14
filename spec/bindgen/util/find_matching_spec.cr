require "../../spec_helper"

private class Finder
  include Bindgen::Util::FindMatching(Bindgen::Parser::Method)

  def find(regex, list)
    find_matching(regex, list).map { |method, match| {method.name, match.to_a} }
  end
end

private def function(name, class_name = "::")
  Bindgen::Parser::Method.build(
    name: name,
    class_name: class_name,
    return_type: Bindgen::Parser::Type::VOID,
    arguments: [] of Bindgen::Parser::Argument,
    type: Bindgen::Parser::Method::Type::StaticMethod,
  )
end

private def find(regex, *functions)
  Finder.new.find(regex, functions.to_a)
end

describe Bindgen::Util::FindMatching do
  context "for a function in the global scope" do
    it "matches the name" do
      find("read_(.*)", function("read_one")).should eq([{"read_one", ["read_one", "one"]}])
    end

    it "matches the whole name only" do
      find("read", function("read_one")).should be_empty
      find("one", function("read_one")).should be_empty
    end
  end

  context "for a function in a namespace" do
    it "matches the qualified name" do
      found = find("storage::read_(.*)", function("read_one", "storage"))
      found.should eq([{"read_one", ["storage::read_one", "one"]}])
    end

    it "matches the qualified name in a nested namespace" do
      found = find("storage::(.*)::read_(.*)", function("read_one", "storage::deep"))
      found.should eq([{"read_one", ["storage::deep::read_one", "deep", "one"]}])
    end

    it "matches the bare name" do
      found = find("read_(.*)", function("read_one", "storage"))
      found.should eq([{"read_one", ["read_one", "one"]}])
    end

    it "prefers the bare name" do
      found = find("(.*)", function("read_one", "storage"))
      found.should eq([{"read_one", ["read_one", "read_one"]}])

      found = find("(.*)_one", function("read_one", "storage"))
      found.should eq([{"read_one", ["read_one", "read"]}])
    end

    it "doesn't match another namespace" do
      find("other::read_(.*)", function("read_one", "storage")).should be_empty
    end
  end
end
