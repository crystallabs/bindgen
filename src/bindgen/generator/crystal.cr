module Bindgen
  module Generator
    # Generator for Crystal wrapper and binding code.
    class Crystal < Base
      include Graph::Visitor

      PLATFORM = Graph::Platform::Crystal

      def initialize(*args)
        super

        @wrote_glue = false
      end

      def write(node : Graph::Container)
        visit_node(node)
      end

      def visit_platform_specific(specific)
        super if specific.platforms.includes? PLATFORM
      end

      def visit_library(library)
        lib_gen = CrystalLib.new(@user_config, Configuration::Generator.dummy, @db)
        lib_gen.write_all library, @io, @depth
      end

      def visit_class(klass)
        return unless @db.try_or(klass.origin.name, true, &.generate_wrapper?)

        scope = "private" if klass.origin.private?
        prefix = "abstract" if klass.abstract?
        suffix = "< #{klass.base_class}" if klass.base_class
        isstruct = @db.try_or(klass.origin.name, false, &.kind.struct?)

        code_block scope, prefix, isstruct ? "struct" : "class", klass.name, suffix do
          write_included_modules(klass.included_modules)
          write_instance_variables(klass.instance_variables)
          super
        end
      end

      def visit_constant(constant)
        formatter = Bindgen::Crystal::Format.new(@db)
        value = formatter.literal(constant.value.class.name, constant.value)
        puts "#{constant.name} = #{value}"
      end

      # Includes the *modules* in the current open scope.
      private def write_included_modules(modules)
        modules.each do |mod|
          puts "include #{mod}"
        end

        puts "" unless modules.empty?
      end

      # Writes the instance *variables* into the current open scope.
      private def write_instance_variables(variables)
        typer = Bindgen::Crystal::Typename.new(@db)

        variables.each do |name, result|
          puts "@#{name} : #{typer.full(result)}"
        end

        puts "" unless variables.empty?
      end

      def visit_namespace(ns)
        code_block "module", ns.name do
          unless @wrote_glue
            # The first module we visit is our main module.  Dump the helper
            # glue code into it.
            puts GlueReader.read
            @wrote_glue = true
          end

          super
        end
      end

      def visit_enum(enumeration)
        typename = Bindgen::Crystal::Typename.new(@db)
        type = Parser::Type.parse(enumeration.origin.type)
        type_name = typename.qualified(*typename.wrapper(type))

        puts "@[Flags]" if enumeration.origin.flags?
        code_block "enum", enumeration.name, ":", type_name do
          enumeration.origin.values.each do |name, value|
            puts "#{name} = #{value}"
          end
        end
      end

      def visit_method(method)
        if call = method.calls[PLATFORM]?
          puts call.body.to_code(call, PLATFORM)
        end
      end

      def code_block(*header, &)
        puts header.reject(&.nil?).join(" ")
        indented { yield }
        puts "end"
      end
    end
  end
end
