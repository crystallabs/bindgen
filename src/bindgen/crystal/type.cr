module Bindgen
  module Crystal
    # Conversion functionality for real Crystal types of any kind to another
    # type by C++ name as defined by user configuration.
    struct Type
      def initialize(@db : TypeDatabase)
      end

      # Resolves a `LibC::` long type to this platforms long size.
      def resolve_long(crystal_type)
        {% begin %}
        # Windows uses `LLP64`, everyone else `LP64`.
        case crystal_type
        {% if flag?(:windows) %}
        when "LibC::Long" then "Int32" # Windows
        when "LibC::ULong" then "UInt32"
        {% else %}
        when "LibC::Long" then "Int64" # Not Windows
        when "LibC::ULong" then "UInt64"
        {% end %}
        when "LibC::LongLong" then "Int64"
        when "LibC::ULongLong" then "UInt64"
        else
          crystal_type
        end
        {% end %}
      end

      # Converts the Crystal *value* to represent a *type*.
      def convert(value, type : Parser::Type)
        if type.base_name == "char" && type.pointer == 1
          return value.to_s # Special case for `(const) char *`
        end

        target_type = @db.try_or(type, type.base_name, &.wrapper_type)
        case resolve_long(target_type)
        when "UInt8"   then as_number(value, &.to_u8)
        when "UInt16"  then as_number(value, &.to_u16)
        when "UInt32"  then as_number(value, &.to_u32)
        when "UInt64"  then as_number(value, &.to_u64)
        when "Int8"    then as_number(value, &.to_i8)
        when "Int16"   then as_number(value, &.to_i16)
        when "Int32"   then as_number(value, &.to_i32)
        when "Int64"   then as_number(value, &.to_i64)
        when "Float32" then as_number(value, &.to_f32)
        when "Float64" then as_number(value, &.to_f64)
        when "String"  then value.to_s
        when "Bool"    then !!value
        when "Nil"     then nil
        else
          raise "Can't convert #{value.inspect} of #{value.class} to #{target_type}"
        end
      end

      private def as_number(value, &)
        case value
        when Number then yield(value)
        when String then yield(value) # Responds to `#to_i` variants
        when Bool   then yield(value ? 1 : 0)
        when nil    then nil
        end
      end
    end
  end
end
