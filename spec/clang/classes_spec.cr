require "./spec_helper"

describe "clang tool classes feature" do
  it "rejects class templates" do
    file = File.tempfile("bindgen-clang-test")
    file.puts("template<typename T> class Templated { T *ptr; };")
    file.flush

    tool = ENV["BINDGEN_BIN"]? || Bindgen::Parser::Runner::BINARY_PATH
    error = IO::Memory.new
    status = Process.run(tool, [file.path, "-c", "Templated", "--", "-x", "c++"], error: error)

    status.normal_exit?.should be_true
    status.success?.should be_false
    error.to_s.should contain("'Templated' is a class template")
  ensure
    file.try(&.delete)
  end
end
