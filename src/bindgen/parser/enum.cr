module Bindgen
  module Parser
    # Enumeration type as found by the clang tool.
    class Enum
      include JSON::Serializable

      # Map of enumerations.
      alias Collection = Hash(String, Enum)

      # Name of the enumeration type.
      getter name : String

      # C++ type name, to be mapped later.
      getter type : String

      # Is this enumeration a flag type?
      @[JSON::Field(key: "isFlags")]
      getter? flags : Bool

      # Is this enumeration anonymous?
      @[JSON::Field(key: "isAnonymous")]
      getter? anonymous : Bool

      # Enum fields
      getter values : Hash(String, Int64)

      # Documentation comment from the C++ source, without comment markers.
      getter doc : String?

      def initialize(@name, @values, @type = "unsigned int", @flags = false, @anonymous = false, @doc = nil)
      end

      def_equals_and_hash @name, @type, @flags, @values
    end
  end
end
