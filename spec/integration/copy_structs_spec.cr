require "./spec_helper"

describe "copied structure functionality" do
  it "works" do
    build_and_run("copy_structs") do
      def instance_var_names(type : T) forall T
        {{ T.instance_vars.map(&.stringify) }}
      end

      # internal compiler error prevents this from working (#9744)
      def union_like?(_x : T) forall T
        #        {% begin %}
        #          {% for var in T.instance_vars %}
        #            offsetof({{ T }}, @{{ var }})
        #            p sizeof(typeof({{ T }}.new.{{ var }}))
        #          {% end %}

        #          {{ T.struct? }} &&
        #            {% for var in T.instance_vars %}
        #              offsetof({{ T }}, @{{ var }}) == 0 &&
        #              sizeof(typeof({{ T }}.new.{{ var }})) <= sizeof({{ T }}) &&
        #            {% end %}
        true
        #        {% end %}
      end

      context "core functionality" do
        it "supports structs" do
          subject = Test::Binding::Point.new
          instance_var_names(subject).should eq(%w{x y}) # ignores `dimensions`
          subject.x.should be_a(Int32)
          subject.y.should be_a(Int32)
        end

        it "supports members of other copied structs" do
          subject = Test::Binding::Line.new
          instance_var_names(subject).should eq(%w{v1 v2})
          subject.v1.should be_a(Test::Binding::Point)
          subject.v2.should be_a(Test::Binding::Point)
        end

        it "supports pointers to other copied structs" do
          subject = Test::Binding::PolyLine.new
          subject.line.should be_a(Pointer(Test::Binding::Line))
          subject.before.should be_a(Pointer(Test::Binding::PolyLine))
          subject.after.should be_a(Pointer(Test::Binding::PolyLine))
        end

        it "supports pointers to converted types as raw pointers" do
          subject = Test::Binding::StringPointer.new
          subject.name.should be_a(Pointer(Void))
          subject.point.should be_a(Pointer(Test::Binding::Point))
        end

        it "supports unions" do
          subject = Test::Binding::PlainUnion.new
          instance_var_names(subject).should eq(%w{x y})
          union_like?(subject).should be_true
        end
      end

      context "nested types" do
        it "supports nested structs" do
          subject = Test::Binding::Nested.new
          subject.c.should be_a(Test::Binding::Nested_Inner2)
          instance_var_names(subject.c).should eq(%w{b})

          subject = Test::Binding::Nested_Inner.new
          instance_var_names(subject).should eq(%w{a})
        end

        it "supports nested unions" do
          subject = Test::Binding::NestedUnion.new
          instance_var_names(subject).should eq(%w{u c d})
          union_like?(subject).should be_true
          instance_var_names(subject.u).should eq(%w{a b})
          union_like?(subject.u).should be_true
        end

        it "supports nested anonymous structs" do
          subject = Test::Binding::Anonymous.new
          instance_var_names(subject).should eq(%w{x0 p0 p2})
          instance_var_names(subject.p0).should eq(%w{x1})
          instance_var_names(subject.p2).should eq(%w{x2 p1})
          instance_var_names(subject.p2.p1).should eq(%w{x3})
        end

        it "ignores inlined anonymous structs" do
          {{ Test::Binding.has_constant?("Anonymous_Unnamed0") }}.should be_false
          {{ Test::Binding.has_constant?("Anonymous_Unnamed0_Unnamed0") }}.should be_false
          {{ Test::Binding.has_constant?("Anonymous_Unnamed1_Unnamed0") }}.should be_false
          {{ Test::Binding.has_constant?("NestedUnion_Unnamed1") }}.should be_false
        end

        it "ignores anonymous structs inside wrapped classes" do
          {{ Test::Binding.has_constant?("Wrapped_Unnamed0") }}.should be_false
        end

        it "does not inline anonymous union members inside a struct" do
          subject = Test::Binding::UnionInStruct.new
          instance_var_names(subject).includes?("c").should be_false
          instance_var_names(subject).includes?("d").should be_false
        end

        it "does not inline anonymous struct members inside a union" do
          subject = Test::Binding::StructInUnion.new
          instance_var_names(subject).includes?("c").should be_false
          instance_var_names(subject).includes?("d").should be_false
        end
      end
    end
  end
end
