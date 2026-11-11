require "./spec_helper"

describe "structures named by a typedef" do
  it "works" do
    build_and_run("typedef_structs") do
      it "copies an anonymous structure" do
        subject = Test::Binding::Anonymous.new(x: 1, y: 2)
        Test::Funcs.sum(subject).should eq(3)
        Test::Funcs.make(3, 4).y.should eq(4)
      end

      it "copies a structure configured by its typedef" do
        Test::Binding::Tagged.new(a: 1).a.should eq(1)
        Test::Binding::Same.new(b: 2).b.should eq(2)
        Test::Binding::Forward.new(c: 3).c.should eq(3)
      end

      it "names members by the typedef, however they're written" do
        subject = Test::Binding::User.new
        subject.anonymous.should be_a(Test::Binding::Anonymous)
        subject.by_typedef.should be_a(Test::Binding::Tagged)
        subject.by_tag.should be_a(Test::Binding::Tagged)
        subject.same.should be_a(Test::Binding::Same)
        subject.forward.should be_a(Pointer(Test::Binding::Forward))
      end

      it "wraps an anonymous structure" do
        subject = Test::Wrapped.new
        subject.z = 5
        subject.z.should eq(5)
        Test::Funcs.wrapped_z(subject).should eq(5)
      end
    end
  end
end
