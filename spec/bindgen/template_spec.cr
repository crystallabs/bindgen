require "../spec_helper"

describe "Template" do
  describe ".from_string" do
    it "constructs the no-op template from nil" do
      Bindgen::Template.from_string(nil).should be_a(Bindgen::Template::None)
    end

    it "can construct a simple template from a string" do
      Bindgen::Template.from_string("%x", simple: true).should eq(
        Bindgen::Template::Basic.new("%x", simple: true))
    end

    it "can construct a full template from a string" do
      expected = Bindgen::Template::Basic.new("%x")
      Bindgen::Template.from_string("%x").should eq(expected)
      Bindgen::Template.from_string("%x", simple: false).should eq(expected)
    end
  end

  describe "#no_op?" do
    it "returns true for the no-op template" do
      Bindgen::Template::None.new.no_op?.should be_true
    end

    it "returns true for string templates with only `%`" do
      Bindgen::Template::Basic.new("%").no_op?.should be_true
      Bindgen::Template::Basic.new("%", simple: true).no_op?.should be_true
    end

    it "returns false for any other templates" do
      conversion1 = Bindgen::Template::Basic.new("%x")
      conversion2 = Bindgen::Template::Basic.new("%x", simple: true)
      conversion3 = Bindgen::Template::Sequence.new(conversion1, conversion2)

      conversion1.no_op?.should be_false
      conversion2.no_op?.should be_false
      conversion3.no_op?.should be_false
    end
  end

  describe "#followed_by" do
    it "composes two templates" do
      conversion1 = Bindgen::Template::Basic.new("%x")
      conversion2 = Bindgen::Template::Basic.new("%y")
      conversion3 = Bindgen::Template::Sequence.new(conversion1, conversion2)

      conversion1.followed_by(conversion2).should eq(conversion3)
    end

    it "is #no_op? only when both templates are #no_op?" do
      op = Bindgen::Template::Basic.new("%x")
      no = Bindgen::Template::None.new

      op.followed_by(op).no_op?.should be_false
      op.followed_by(no).no_op?.should be_false
      no.followed_by(op).no_op?.should be_false
      no.followed_by(no).no_op?.should be_true
    end
  end

  describe "None#template" do
    it "returns the code unmodified" do
      Bindgen::Template::None.new.template("123").should eq("123")
    end
  end

  describe "Basic#template" do
    it "substitutes % with the supplied code" do
      Bindgen::Template::Basic.new("a%b%c").template("123").should eq("a123b123c")
    end

    it "may access environment variables if it is a full template" do
      key, value = ENV.first
      Bindgen::Template::Basic.new("%{#{key}}%").template("123").should eq("123#{value}123")
    end

    it "substitutes %% with % if it is a simple template" do
      Bindgen::Template::Basic.new("%%a%%%b%%%%c", simple: true).template("123").should eq("%a%123b%%c")
    end
  end

  describe "Sequence#template" do
    it "composes multiple templates" do
      a_conv = Bindgen::Template::Basic.new("%_a")
      b_conv = Bindgen::Template::Basic.new("%_b")

      conversion = Bindgen::Template::Sequence.new(a_conv, b_conv)
      conversion.template("c").should eq("c_a_b")

      conversion = Bindgen::Template::Sequence.new(a_conv, a_conv, a_conv, b_conv, b_conv, a_conv)
      conversion.template("c").should eq("c_a_a_a_b_b_a")
    end
  end
end
