module Bindgen
  module Parser
    # Stores the signature of a function `Type`, like `int (char)` of the
    # function pointer `int (*)(char)`.
    class Prototype
      include JSON::Serializable

      # Return type
      @[JSON::Field(key: "returnType")]
      getter return_type : Type

      # Parameter types
      getter arguments : Array(Type)

      # Does the signature end in `...`?
      @[JSON::Field(key: "isVariadic")]
      getter? variadic : Bool

      # Is the function called like other functions of the target?  This is
      # `false` for a calling convention set by an attribute, like `ms_abi` on
      # Linux.
      @[JSON::Field(key: "isDefaultCallingConvention")]
      getter? default_calling_convention : Bool

      def initialize(@return_type, @arguments, @variadic = false, @default_calling_convention = true)
      end

      def_equals_and_hash @return_type, @arguments, @variadic, @default_calling_convention
    end
  end
end
