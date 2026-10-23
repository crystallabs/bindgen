require "../../spec_helper"

private def klass(methods)
  Bindgen::Parser::Class.new(name: "Foo", methods: methods)
end

private def method(name, arguments)
  Parser.method(name, "Foo", Parser.void_type, arguments)
end

describe Bindgen::Parser::Class do
  describe "#wrap_methods" do
    it "keeps the variant with more arguments of the same Crystal signature" do
      # `f(int a, Bar b = Bar(), bool *ok = nullptr)`, split at `b`
      method = method("f", [
        Parser.argument("a", "int"),
        Parser.argument("b", "Bar", has_default: true),
        Parser.argument("ok", "bool *", true),
      ])

      names = klass([method]).wrap_methods.map { |m| m.arguments.map(&.name) }
      names.should eq([["a"], ["a", "b", "ok"]])
    end

    it "keeps the longer of two methods differing in C++ only" do
      shorter = method("try_acquire", [] of Bindgen::Parser::Argument)
      longer = method("tryAcquire", [Parser.argument("n", "int", 1_i64)])

      klass([shorter, longer]).wrap_methods.map(&.name).should eq(["tryAcquire"])
      klass([longer, shorter]).wrap_methods.map(&.name).should eq(["tryAcquire"])
    end

    it "keeps the first of two methods of equal length" do
      first = method("tryLock", [Parser.argument("n", "int")])
      second = method("try_lock", [Parser.argument("n", "int")])

      klass([first, second]).wrap_methods.map(&.name).should eq(["tryLock"])
    end
  end
end
