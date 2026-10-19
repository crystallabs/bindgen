require "../spec_helper"

describe Bindgen::Tool do
  it "reads the configuration again after finding paths, so conditions see the found variables" do
    ENV.delete("BINDGEN_TOOL_SPEC_DIR")
    root = "#{__DIR__}/tool"
    path = "#{root}/found.yml"

    config = Bindgen::ConfigReader.from_file(Bindgen::Configuration, path)
    config.classes.has_key?("Found").should be_false

    tool = Bindgen::Tool.new(root, config, show_stats: false, config_path: path)
    tool.run!.should eq(0)
    ENV["BINDGEN_TOOL_SPEC_DIR"]?.should eq(root)
    tool.config.classes["Found"]?.should eq("Found")
  ensure
    ENV.delete("BINDGEN_TOOL_SPEC_DIR")
  end
end
