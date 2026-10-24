require "./spec_helper"

describe "deprecated methods kept, and global ignore_methods" do
  it "works" do
    build_and_run("deprecated_kept") do
      context "deprecated methods" do
        it "are kept under @[Deprecated]" do
          api = Test::Api.new
          api.fresh.should eq(1)
          api.stale.should eq(2)
          api.value(4, 5).should eq(9)
          Test::Api.old_count.should eq(4)
          Test.old_helper.should eq(6)

          {% begin %}
            {% stale = Test::Api.methods.find(&.name.== "stale") %}
            {{ stale.annotation(Deprecated) ? true : false }}.should be_true
            {% fresh = Test::Api.methods.find(&.name.== "fresh") %}
            {{ fresh.annotation(Deprecated) ? true : false }}.should be_false
            {% old = Test::Api.class.methods.find(&.name.== "old_count") %}
            {{ old.annotation(Deprecated) ? true : false }}.should be_true
          {% end %}
        end
      end

      context "global ignore_methods" do
        it "drops the methods in every class" do
          noisy = Test::Noisy.new
          noisy.keep.should eq(1)
          noisy.responds_to?(:drop).should be_false
          Test::Quiet.new.responds_to?(:drop).should be_false
          noisy.responds_to?(:drop_by_regex).should be_false
        end

        it "drops a single overload by signature" do
          noisy = Test::Noisy.new
          noisy.drop_one(2.5).should eq(20)
          {{ Test::Noisy.methods.select(&.name.== "drop_one").size }}.should eq(1)
        end
      end
    end
  end
end
