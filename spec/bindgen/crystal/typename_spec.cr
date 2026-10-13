require "../../spec_helper"

private def result(cpp_type, type_name, pointer = 0, reference = false, nilable = false)
  Bindgen::Call::Result.new(
    type: Bindgen::Parser::Type.parse(cpp_type),
    type_name: type_name,
    reference: reference,
    pointer: pointer,
    nilable: nilable,
  )
end

describe Bindgen::Crystal::Typename do
  db = Bindgen::TypeDatabase.new(Bindgen::TypeDatabase::Configuration.new, "boehmgc-cpp")
  subject = Bindgen::Crystal::Typename.new(db)

  describe "#full" do
    context "if a type is expected" do
      it "formats a plain type" do
        subject.full(result("int", "Int32")).should eq("Int32")
      end

      it "formats pointers and references" do
        subject.full(result("int **", "Int32", pointer: 2)).should eq("Int32**")
        subject.full(result("int &", "Int32", reference: true)).should eq("Int32*")
      end

      it "formats a nilable type" do
        subject.full(result("int *", "Int32", pointer: 1, nilable: true)).should eq("Int32*?")
      end

      it "formats C arrays with reversed extents" do
        subject.full(result("int [3][2]", "Int32")).should eq("Int32[2][3]")
        subject.full(result("int *[4]", "Int32", pointer: 1)).should eq("Int32*[4]")
      end
    end

    context "if no type is expected" do
      it "formats a plain type" do
        subject.full(result("int", "Int32"), expects_type: false).should eq("Int32")
      end

      it "formats pointers and references" do
        subject.full(result("int **", "Int32", pointer: 2), expects_type: false).should eq("Pointer(Pointer(Int32))")
        subject.full(result("int &", "Int32", reference: true), expects_type: false).should eq("Pointer(Int32)")
      end

      it "formats C arrays as StaticArray" do
        subject.full(result("int [3][2]", "Int32"), expects_type: false).should eq("StaticArray(StaticArray(Int32, 2), 3)")
        subject.full(result("int *[4]", "Int32", pointer: 1), expects_type: false).should eq("StaticArray(Pointer(Int32), 4)")
      end
    end
  end
end
