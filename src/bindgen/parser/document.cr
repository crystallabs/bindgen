require "./enum"

module Bindgen
  module Parser
    # Document as returned by the clang tool.
    class Document
      include JSON::Serializable

      # Version of the format this bindgen understands.  Has to match
      # `BG_FORMAT_VERSION` of the clang tool.
      FORMAT_VERSION = 1

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
        @format_version = FORMAT_VERSION
      )
      end

      # Raises if the document was written by a clang tool of another version.
      def check_format_version! : Nil
        return if @format_version == FORMAT_VERSION

        raise "The clang tool writes format version #{@format_version}, but " \
              "version #{FORMAT_VERSION} is required.  Rebuild it: " \
              "Run `cmake . && make` in bindgen's clang/ directory."
      end
    end
  end
end
