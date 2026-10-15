require "./enum"

module Bindgen
  module Parser
    # Document as returned by the clang tool.
    class Document
      include JSON::Serializable

      # Version of the format this bindgen understands.  Has to match
      # `BG_FORMAT_VERSION` of the clang tool.
      FORMAT_VERSION = 9

      # Version of the format the document was written in.
      @[JSON::Field(key: "version")]
      getter format_version : Int32 = 0

      getter enums : Enum::Collection
      getter classes : Class::Collection
      getter macros : Macro::Collection
      getter functions : Method::Collection = Method::Collection.new

      # For testing purposes.
      def initialize(
        @enums = Enum::Collection.new,
        @classes = Class::Collection.new,
        @macros = Macro::Collection.new,
        @functions = Method::Collection.new,
        @format_version = FORMAT_VERSION,
      )
      end

      # Parses the output of the clang tool.  Raises if it was written in
      # another format version: Its fields may not match, so this is checked
      # before parsing the rest.
      def self.parse(json : String) : self
        check_format_version!(read_format_version(json))
        from_json(json)
      end

      # Reads the format version.  The clang tool writes it first.
      private def self.read_format_version(json) : Int32
        pull = JSON::PullParser.new(json)
        pull.read_begin_object
        return 0 if pull.kind.end_object?

        pull.read_object_key == "version" ? pull.read_int.to_i32 : 0
      end

      # Raises if *version* isn't the one this bindgen understands.
      def self.check_format_version!(version) : Nil
        return if version == FORMAT_VERSION

        raise "The clang tool writes format version #{version}, but " \
              "version #{FORMAT_VERSION} is required.  Rebuild it: " \
              "Run `cmake . && make` in bindgen's clang/ directory."
      end
    end
  end
end
