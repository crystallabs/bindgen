require "../../spec_helper"

describe Bindgen::Parser::Document do
  describe "#check_format_version!" do
    it "accepts the current format version" do
      version = Bindgen::Parser::Document::FORMAT_VERSION
      doc = Bindgen::Parser::Document.from_json(%<{"version": #{version}, "enums": {}, "classes": {}, "macros": []}>)
      doc.check_format_version!
    end

    it "rejects another format version" do
      version = Bindgen::Parser::Document::FORMAT_VERSION + 1
      doc = Bindgen::Parser::Document.from_json(%<{"version": #{version}, "enums": {}, "classes": {}, "macros": []}>)
      expect_raises(Exception, /format version #{version}/) { doc.check_format_version! }
    end

    it "rejects a document without format version" do
      doc = Bindgen::Parser::Document.from_json(%<{"enums": {}, "classes": {}, "macros": []}>)
      expect_raises(Exception, /format version 0/) { doc.check_format_version! }
    end
  end
end
