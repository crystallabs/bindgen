module Bindgen
  module Crystal
    # Formatter for Crystal style code.
    struct Format
      def initialize(@db : TypeDatabase)
      end

      # Formats *arg* as `type name`.  If *binding* is `true`, treat this as
      # argument for a `fun` declaration.
      def argument(arg : Call::Argument, idx, expose_default = true, binding = false) : String
        argument = Argument.new(@db)
        typer = Typename.new(@db)

        # Support variadic argument
        if arg.is_a?(Call::VariadicArgument)
          if binding
            return "..."
          else
            return arg.name
          end
        end

        value = arg.default_value
        if value != nil && expose_default
          stringified = literal(arg.type_name, value)

          if stringified.nil? && value.is_a?(Number)
            stringified = qualified_enum_name arg.type, enum_value(value)
          end

          default = " = #{stringified}" if stringified
        end

        if arg.is_a?(Call::ProcArgument) && arg.block?
          prefix = "&"
        end

        if arg.is_a?(Call::TypeArgument)
          meta = ".class"
        end

        "#{prefix}#{argument.name(arg, idx)} : #{typer.full arg}#{meta}#{default}"
      end

      # Formats *arguments* as `name : type, ...`.  If *binding* is `true`,
      # treats this as argument for a `fun` declaration.
      def argument_list(arguments : Enumerable(Call::Argument), binding = false) : String
        first_optional = arguments.rindex(&.default_value.nil?) || -1

        arguments.map_with_index do |arg, idx|
          argument(arg, idx, expose_default: idx > first_optional, binding: binding)
        end.join(", ")
      end

      # Formats *arguments* as `*, name : type, ...`.
      def named_argument_list(arguments : Enumerable(Call::Argument), binding = false) : String
        String.build do |b|
          b << '*'
          arguments.each_with_index do |arg, idx|
            b << ", " << argument(arg, idx)
          end
        end
      end

      # Generates a literal value suitable for Crystal code, using the *value*
      # of *type_name*.  *type_name* is a completely deduced Crystal type-name.
      #
      # Returns `nil` if *type_name* is unknown (It's not built-in).  Try
      # `#qualified_enum_name` in that case if it might be an enum.
      def literal(type_name, value) : String?
        case value
        when String then value.inspect
        when Number then number_literal(type_name, value)
        when Bool
          if type_name == "Bool"
            value.to_s
          else # Special case: This is an Object with a null-pointer.
            "nil"
          end
        end
      end

      # Returns the number literal of *type_name* with *value*.  The result is
      # valid a Crystal literal, and can be directly written.
      def number_literal(type_name, value) : String?
        if suffix = number_literal_suffix(type_name)
          if type_name == "Float32"
            value = value.to_f32
          elsif type_name == "Float64"
            value = value.to_f64
          elsif !value.is_a?(Int)
            value = value.to_i
          end

          "#{value}#{suffix}" # TODO: Literal thousand's grouping
        end
      end

      # The *value* as the `Int64` enumerators are stored as.  An unsigned value
      # above `Int64::MAX` wraps around, like its enumerator did.
      private def enum_value(value : Number) : Int64
        value.is_a?(Float) ? value.to_i64 : value.to_i64!
      end

      # Returns the qualified name of *value* in the enum called *enum_name*.
      # Builds a `.flags(...)` list if the enum turns out to be a `@[Flags]`.
      def qualified_enum_name(type : Parser::Type, value : Int) : String?
        rules = @db[type]?
        return if rules.nil?

        enum_node = rules.graph_node.as?(Graph::Enum)
        return if enum_node.nil?

        enumeration = enum_node.origin

        enum_name = rules.wrapper_type
        if enumeration.flags?
          "#{enum_name}#{format_flags_enum(enumeration.values, value)}"
        else
          if key = enumeration.values.key_for?(value)
            "#{enum_name}::#{key}"
          else
            "#{enum_name}.from_value(#{value})"
          end
        end
      end

      # Generates the flag-list of an enum.
      private def format_flags_enum(values, bitmask) : String
        names = [] of String

        # Find all names of all set bits in *bitmask*
        (0...64).each do |bit_idx|
          value = 1u64 << bit_idx
          next if (bitmask & value) == 0

          # Does a name exist?
          if name = values.key_for?(value)
            names << name
          else # There's no name, fallback!
            return ".from_value(#{bitmask})"
          end
        end

        if names.empty?
          "::None"
        else # All names found: Build a nice `.flags` list
          ".flags(#{names.join(", ")})"
        end
      end

      # Returns the literal-suffix for Crystal code, to signify a literal
      # matching the intended *type_name*.
      #
      # If *type_name* is unknown, returns `nil`.
      def number_literal_suffix(type_name) : String?
        case type_name
        when "UInt8"   then "u8"
        when "UInt16"  then "u16"
        when "UInt32"  then "u32"
        when "UInt64"  then "u64"
        when "Int8"    then "i8"
        when "Int16"   then "i16"
        when "Int32"   then "" # Default type, don't clutter
        when "Int64"   then "i64"
        when "Float32" then "f32"
        when "Float64" then "f64"
        end
      end
    end
  end
end
