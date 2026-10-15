require "./spec_helper"

describe "documentation comments" do
  it "works" do
    build_and_run("doc_comments") do
      it "keeps the wrappers working" do
        Test::Documented.new.add(1).should eq(4)
        Test::Documented.new.scale(2).should eq(20)
        Test::Documented.new.value.should eq(1)
        Test::BoxInt.new.get.should eq(5)
        Test::Funcs.increment(1).should eq(2)
      end
    end

    output = File.read("#{__DIR__}/tmp/doc_comments.cr")

    # Classes, with each paragraph
    output.should contain("  # A documented class.\n  #\n  # It has a second paragraph.\n  class Documented\n")

    # Constructors and methods, including each overload of default arguments
    output.should match(/# Builds a documented instance\.\n\s+def initialize\(\)/)
    output.should match(/# Adds \*a\* and \*b\* to the value\.\n\s+# @param a The first summand\.\n\s+def add\(a : Int32, b : Int32 = 2\)/)
    output.should match(/# there's one overload with and one without it\.\n\s+def scale\(x : Int32, factor : Int32\)/)
    output.should match(/# there's one overload with and one without it\.\n\s+def scale\(x : Int32\)/)

    # Plain comments aren't copied by default
    output.should_not contain("A plain comment")

    # Instance properties, for both the getter and the setter
    output.should match(/# The current value\.\n\s+def value\b/)
    output.should match(/# The current value\.\n\s+def value=/)
    output.should match(/# A counter shared by all instances\.\n\s+def self\.counter\b/)

    # Enumerations, class template instantiations, and functions
    output.should contain("# Colors a documented class can have.\n  enum Color")
    output.should match(/# A box holding a value\.\n\s+class BoxInt/)
    output.should match(/# Returns the boxed value\.\n\s+def get\b/)
    output.should match(/# Adds one to \*x\*\.\n\s+def self\.increment\b/)
  end
end
