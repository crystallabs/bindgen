require "./spec_helper"

describe "the argument translation functionality" do
  it "works" do
    build_and_run("arguments") do
      include Test

      macro check_default_arg(method, type, value)
        {% m = Test::Defaults.methods.find(&.name.stringify.== method) %}
        {{ m.args.size }}.should eq(1)
        # For debugging, dump the arguments here as string.
        # {{ m.args.stringify }}
        # {{ m.name }}

        (typeof({{ m.args.first.restriction }}) == typeof({{ type }})).should be_true
        ({{ m.args.first.default_value }}).should eq {{ value }}
      end

      it "copies default of type Int32" do
        check_default_arg("default_int32", Int32, 123)
      end

      it "copies default of enum type above Int32::MAX" do
        check_default_arg("default_large_enum", Test::Bits, Test::Bits::Everything)
      end

      it "copies default of enum type" do
        check_default_arg("default_enum", Test::Numeral, Test::Numeral::Second)
      end

      it "copies default of type Bool" do
        check_default_arg("default_true", Bool, true)
        check_default_arg("default_false", Bool, false)
      end

      it "copies default of type String" do
        check_default_arg("default_string", String, "Okay")
      end

      it "deduces nilability of pointer type defaulting to NULL" do
        check_default_arg("nilable", Test::Defaults?, nil)
      end
    end
  end
end
