require "../../spec_helper"

private def with_dependency(content, &)
  name = "loader_spec_#{rand 1..1_000_000}"
  full_path = "#{Dir.tempdir}/#{name}.yml"
  File.write(full_path, content)
  yield name, full_path
ensure
  File.delete(full_path) if full_path
end

describe Bindgen::ConfigReader::Loader do
  subject = Bindgen::ConfigReader::Loader.new
  base_file = "#{Dir.tempdir}/the_root.yml" # Fake path

  describe "#load" do
    context "with .yml suffix" do
      it "loads the dependency" do
        with_dependency "Okay" do |name|
          subject.load(base_file, "#{name}.yml").should eq({"Okay", "#{Dir.tempdir}/#{name}.yml"})
        end
      end

      it "raises when a dot is the dependency name" do
        expect_raises(Bindgen::ConfigReader::Loader::Error, /includes dots/) do
          subject.load(base_file, "../foo.yml")
        end
      end

      it "raises when the dependency name is absolute" do
        expect_raises(Bindgen::ConfigReader::Loader::Error, /absolute path/) do
          subject.load(base_file, "/etc/passwd.yml")
        end
      end

      it "raises when the dependency name is absolute (backslash)" do
        expect_raises(Bindgen::ConfigReader::Loader::Error, /absolute path/) do
          subject.load(base_file, "\\Windows\\something.yml")
        end
      end

      it "raises when the dependency name looks like a URL" do
        expect_raises(Bindgen::ConfigReader::Loader::Error, /absolute path/) do
          subject.load(base_file, "C:/Windows/something.yml")
        end
      end
    end

    context "without .yml suffix" do
      it "loads the dependency" do
        with_dependency "Okay" do |name|
          subject.load(base_file, name).should eq({"Okay", "#{Dir.tempdir}/#{name}.yml"})
        end
      end

      it "raises when a dot is the dependency name" do
        expect_raises(Bindgen::ConfigReader::Loader::Error, /includes dots/) do
          subject.load(base_file, "../foo")
        end
      end

      it "raises when the dependency name is absolute" do
        expect_raises(Bindgen::ConfigReader::Loader::Error, /absolute path/) do
          subject.load(base_file, "/etc/passwd")
        end
      end

      it "raises when the dependency name is absolute (backslash)" do
        expect_raises(Bindgen::ConfigReader::Loader::Error, /absolute path/) do
          subject.load(base_file, "\\Windows\\something")
        end
      end

      it "raises when the dependency name looks like a URL" do
        expect_raises(Bindgen::ConfigReader::Loader::Error, /absolute path/) do
          subject.load(base_file, "C:/Windows/something")
        end
      end
    end
  end
end
