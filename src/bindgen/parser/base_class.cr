module Bindgen
  module Parser
    # Describes a class which is derived from another `Bindgen::Class`.
    class BaseClass
      include JSON::Serializable

      # Is this inheritance virtual?
      @[JSON::Field(key: "isVirtual")]
      getter? virtual : Bool

      # Does the `Bindgen::Class` derive its constructors from this class?
      @[JSON::Field(key: "inheritedConstructor")]
      getter? inherited_constructor : Bool

      # Fully qualified name of the base class.
      getter name : String

      # Visibility of the base class.
      getter access = Bindgen::Parser::AccessSpecifier::Public

      # Offset of the base in the derived class.  A pointer to the derived
      # class can only be used as pointer to the base if it's `0`.
      getter offset = 0

      def initialize(@name, @access = AccessSpecifier::Public, @virtual = false, @inherited_constructor = false, @offset = 0)
      end

      delegate public?, protected?, private?, to: @access
    end
  end
end
