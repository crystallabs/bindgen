require "./type"
require "./value"

module Bindgen
  module Parser
    # Describes a method argument.
    class Argument < Type
      include JSON::Serializable

      # Does this argument have a default value?
      @[JSON::Field(key: "hasDefault")]
      getter? has_default : Bool

      # Is this the vararg (`...`) argument?
      @[JSON::Field(key: "isVariadic")]
      getter? variadic : Bool

      # Name of this argument.
      getter name : String

      # Default value for this argument, if an initializer literal is found.
      @[JSON::Field(converter: Bindgen::Parser::ValueConverter)]
      getter value : DefaultValueTypes?

      def initialize(
        @name, @base_name, @full_name, @const, @reference, @move, @builtin,
        @void, @pointer, @template, @kind = Type::Kind::Class,
        @has_default = false, @value = nil, @nilable = false, @variadic = false,
        @extents = Array(UInt64).new, @array_pointer = 0,
      )
      end

      def initialize(@name, type : Type, @has_default = false, @value = nil)
        @base_name = type.base_name
        @full_name = type.full_name
        @const = type.const?
        @reference = type.reference?
        @move = type.move?
        @builtin = type.builtin?
        @void = type.void?
        @variadic = false
        @pointer = type.pointer
        @extents = type.extents
        @array_pointer = type.array_pointer
        @kind = type.kind
        @template = type.template
        @nilable = type.nilable?
      end

      def_equals_and_hash @base_name, @full_name, @const, @reference, @move,
        @builtin, @void, @pointer, @has_default, @name, @value, @nilable,
        @template, @extents, @array_pointer

      # Does this argument have an exposed default value?
      def has_exposed_default?
        @has_default && @value != nil
      end

      # If this is a pointer-type, does it default to `nullptr` in C++?
      def defaults_to_nil? : Bool
        @pointer > 0 && value == true
      end

      # Assume that if the argument defaults to `nullptr`, that it is nilable.
      def nilable? : Bool
        defaults_to_nil? || super
      end

      # Returns a copy of this argument without a default value.
      def without_default : Argument
        Argument.new(
          name: @name,
          base_name: @base_name,
          full_name: @full_name,
          const: @const,
          reference: @reference,
          move: @move,
          builtin: @builtin,
          void: @void,
          pointer: @pointer,
          extents: extents,
          array_pointer: @array_pointer,
          template: @template,
          kind: @kind,
          has_default: false,
          value: nil,
          nilable: nilable?,
        )
      end

      # Merges this argument with *other*.  Only merges defaultness, its value
      # and nil-ability.  For the value, this argument takes precedence over
      # *other*.
      def merge(other : Argument)
        Argument.new(
          name: @name,
          base_name: @base_name,
          full_name: @full_name,
          const: @const,
          reference: @reference,
          move: @move,
          builtin: @builtin,
          void: @void,
          pointer: @pointer,
          extents: extents,
          array_pointer: @array_pointer,
          template: @template,
          kind: @kind,
          has_default: @has_default || other.has_default?,
          value: @value || other.value,
          nilable: nilable? || other.nilable?,
        )
      end

      # Performs type substitution on the type part of this argument using the
      # given *replacements*.
      def substitute_type(replacements : Hash(String, Type)) : Argument
        Argument.new(
          name: @name,
          type: substitute(replacements),
          has_default: @has_default,
          value: @value,
        )
      end

      # Substitutes all uses of *name* on the type part of this argument with
      # the given *type*.
      def substitute_type(name : String, with type : Type) : Argument
        Argument.new(
          name: @name,
          type: substitute(name, type),
          has_default: @has_default,
          value: @value,
        )
      end

      # Checks if the type-part of this equals the type-part of *other*.
      def type_equals?(other : Type)
        {% for i in %i[base_name full_name const reference move builtin void pointer extents array_pointer template] %}
          return false if @{{ i.id }} != other.@{{ i.id }}
        {% end %}

        true
      end
    end
  end
end
