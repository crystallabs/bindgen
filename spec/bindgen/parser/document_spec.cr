require "../../spec_helper"

describe Bindgen::Parser::Document do
  describe ".parse" do
    it "accepts the current format version" do
      version = Bindgen::Parser::Document::FORMAT_VERSION
      Bindgen::Parser::Document.parse(%<{"version": #{version}, "enums": {}, "classes": {}, "macros": []}>)
    end

    it "rejects another format version" do
      version = Bindgen::Parser::Document::FORMAT_VERSION + 1
      json = %<{"version": #{version}, "enums": {}, "classes": {}, "macros": []}>
      expect_raises(Exception, /format version #{version}/) { Bindgen::Parser::Document.parse(json) }
    end

    it "rejects a document without format version" do
      json = %<{"enums": {}, "classes": {}, "macros": []}>
      expect_raises(Exception, /format version 0/) { Bindgen::Parser::Document.parse(json) }
    end

    it "rejects an old document before parsing its fields" do
      # Format 1 lacks `hasUserDeclaredConstructor`.
      json = %<{"version": 1, "enums": {}, "macros": [], "classes": {"Foo": {"name": "Foo"}}}>
      expect_raises(Exception, /format version 1/) { Bindgen::Parser::Document.parse(json) }
    end
  end
end
