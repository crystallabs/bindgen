module Bindgen
  module Generator
    # Generator for C functions calling C++ code.
    class Cpp < Base
      include Graph::Visitor

      PLATFORM = Graph::Platform::Cpp

      CONSTANT_TYPES = {
        Bool    => "bool",
        UInt8   => "uint8_t",
        UInt16  => "uint16_t",
        UInt32  => "uint32_t",
        UInt64  => "uint64_t",
        Int8    => "int8_t",
        Int16   => "int16_t",
        Int32   => "int32_t",
        Int64   => "int64_t",
        String  => "const char *",
        Float32 => "float",
        Float64 => "double",
      }

      def write(node : Graph::Container)
        visit_children(node)
      end

      # Add additional includes
      protected def enter_section(section)
        @user_config.parser.files.each do |path|
          templated = Util.template(path, replacement: nil)
          puts "#include <#{templated}>"
        end

        puts ""
      end

      def visit_platform_specific(specific)
        super if specific.platforms.includes? PLATFORM
      end

      def visit_library(_library)
        nil # Don't visit a `lib`
      end

      def visit_class(klass)
        return unless @db.try_or(klass.origin.name, true, &.generate_wrapper?)
        begin_section klass.name
        super
      end

      def visit_constant(constant)
        type_name = CONSTANT_TYPES[constant.value.class]
        puts "static #{type_name} #{constant.name} = #{constant.value.inspect};"
      end

      def visit_alias(alias_name)
        typer = Bindgen::Cpp::Typename.new
        type_name = typer.full(alias_name.origin)
        puts "typedef #{type_name} #{alias_name.name};"
      end

      def visit_struct(structure)
        prototype = type_prototype :struct, structure.name, structure.base_class
        puts "#{prototype} {"
        indented do
          if structure.tag?(Graph::Struct::INHERIT_CONSTRUCTORS_TAG)
            base = base_class_of(structure)
            ctor = Graph::Path.from(base).last_part
            puts "using #{base}::#{ctor};" # C++11
          end

          if structure.tag?(Graph::Struct::COPY_BASE_CONSTRUCTOR_TAG)
            base = base_class_of(structure)
            puts "#{structure.name}(const #{base} &other) : #{base}(other) { }"
          end

          structure.fields.each do |name, type|
            puts "#{type.type_name} #{name};"
          end

          super # Implement methods, if any
        end
        puts "};"
      end

      def visit_method(method)
        if call = method.calls[PLATFORM]?
          puts call.body.to_code(call, PLATFORM)
        end
      end

      private def type_prototype(kind, name, base) : String
        suffix = " : public #{base}" if base
        "#{kind} #{name}#{suffix}"
      end

      # Returns the base class of *structure*, which is tagged to use its
      # constructors and thus must have one.
      private def base_class_of(structure) : String
        structure.base_class || raise "BUG: Struct #{structure.name} has no base class"
      end
    end
  end
end
