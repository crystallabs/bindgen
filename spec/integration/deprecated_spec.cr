require "./spec_helper"

describe "ignore_deprecated feature" do
  it "works" do
    build_and_run("deprecated") do
      it "drops deprecated methods, keeping the other overloads" do
        api = Test::Api.new
        api.fresh.should eq(1)
        api.responds_to?(:stale).should be_false
        api.value(4).should eq(4)
        {{ Test::Api.methods.select(&.name.== "value").size }}.should eq(1)
        api.responds_to?(:scaled).should be_false
      end

      it "drops deprecated static methods and functions" do
        Test::Api.count.should eq(3)
        Test::Api.responds_to?(:old_count).should be_false
        Test.helper.should eq(5)
        Test.responds_to?(:old_helper).should be_false
      end
    end
  end
end
