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

      # Section of the declarations shared by the files of a multi-file setup:
      # the type aliases, structures and constants.
      DECLARATIONS_SECTION = "bindgen_declarations"

      # Section of the functions outside of a class in a multi-file setup.
      FUNCTIONS_SECTION = "bindgen_functions"

      # What a multi-file setup is writing: the shared declarations first, then
      # the functions, a file per class.  `nil` in a single-file setup, which
      # writes both as they come.
      @pass : Symbol?

      # The sections of the classes being visited, innermost last.
      @class_sections = [] of String

      # Depth of the structures being visited.
      @struct_depth = 0

      def write(node : Graph::Container)
        unless multi_file?
          visit_children(node)
          return
        end

        @pass = :declarations
        begin_section DECLARATIONS_SECTION
        visit_children(node)

        @pass = :functions
        visit_children(node)
      end

      # Add additional includes
      protected def enter_section(section)
        unless section.in?(SINGLE_FILE_SECTION, DECLARATIONS_SECTION)
          # Which includes the parsed files itself.
          puts %[#include "#{File.basename(section_path(DECLARATIONS_SECTION))}"]
          puts ""
          return
        end

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

        # Named by the path below the module: nested classes share names.
        @class_sections << klass.full_path[1..].join("::", &.name)
        super
        @class_sections.pop
      end

      def visit_constant(constant)
        return if @pass == :functions
        type_name = CONSTANT_TYPES[constant.value.class]
        puts "static #{type_name} #{constant.name} = #{constant.value.inspect};"
      end

      def visit_alias(alias_name)
        return if @pass == :functions
        typer = Bindgen::Cpp::Typename.new
        type_name = typer.full(alias_name.origin)
        puts "typedef #{type_name} #{alias_name.name};"
      end

      def visit_struct(structure)
        return if @pass == :functions
        @struct_depth += 1

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
            default = structure.field_defaults[name]?
            puts "#{type.type_name} #{name}#{" = #{default}" if default};"
          end

          super # Implement methods, if any
        end
        puts "};"
        @struct_depth -= 1
      end

      # The methods of a structure are part of its declaration.
      def visit_method(method)
        call = method.calls[PLATFORM]?
        return unless call

        if @struct_depth == 0
          return if @pass == :declarations
          begin_section(@class_sections.last? || FUNCTIONS_SECTION)
        end

        puts call.body.to_code(call, PLATFORM)
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
