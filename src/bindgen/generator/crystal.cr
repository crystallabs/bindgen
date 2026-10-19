module Bindgen
  module Generator
    # Generator for Crystal wrapper and binding code.
    class Crystal < Base
      include Graph::Visitor

      PLATFORM = Graph::Platform::Crystal

      def initialize(*args)
        super

        @wrote_glue = false

        # Classes and enums that will be written, but haven't been yet.
        @unwritten = Set(Graph::Class | Graph::Enum).new

        # Classes held back until their superclass, and the types their
        # included modules name, have been written.
        @deferred = [] of Graph::Class
      end

      def write(node : Graph::Container)
        collect_classes(node)
        visit_node(node)

        unless @deferred.empty?
          raise "BUG: Dependencies of #{@deferred.map(&.diagnostics_path).join(", ")} were never written"
        end
      end

      # Visits all children of *container*.  After each child, writes the
      # deferred classes inside *container* which became writable.
      def visit_children(container : Graph::Container)
        container.nodes.each do |child|
          visit_node(child)
          write_deferred(container) unless @deferred.empty?
        end
      end

      def visit_platform_specific(specific)
        super if specific.platforms.includes? PLATFORM
      end

      def visit_library(library)
        lib_gen = CrystalLib.new(@user_config, Configuration::Generator.dummy, @db)
        lib_gen.write_all library, @io, @depth
        write_bit_field_methods(library)
      end

      # Reopens the `lib struct`s and `lib union`s with bit-fields to add
      # their methods.
      private def write_bit_field_methods(library)
        library.nodes.each do |node|
          next unless node.is_a?(Graph::Struct | Graph::CppUnion)
          next if node.bit_fields.empty?

          path = "#{library.name}::#{node.name}"
          # The first member is at the address of the structure.
          address = "pointerof(@#{node.fields.first_key}).as(#{path}*)"

          code_block "struct", path do
            node.bit_fields.each_with_index do |field, index|
              puts "" if index > 0
              write_bit_field(field, library.name, address)
            end
          end
        end
      end

      # Writes the getter and setter of the bit-*field* of a `lib struct`,
      # which is at *address*.  They call the C++ accessors in the `lib`
      # *library*, if any, or else shift and mask the storage.
      private def write_bit_field(field, library, address)
        storage = "@#{field.storage}"
        mask = "#{field.storage_type}.new!(0x#{(UInt64::MAX >> (64 - field.width)).to_s(16)}_u64)"

        write_doc field.doc
        code_block "def", "#{field.name} : #{field.type_name}" do
          if getter = field.getter_fun
            puts "#{library}.#{getter}(#{address})"
          elsif field.bool
            puts "(#{storage} >> #{field.shift}) & 1 != 0"
          elsif signed_type = field.signed_type
            # Shift the sign bit to the top, and back with sign extension.
            left = field.unit_bits - field.shift - field.width
            value = "#{signed_type}.new!(#{storage} << #{left}) >> #{field.unit_bits - field.width}"
            value = "#{field.type_name}.new!(#{value})" if signed_type != field.type_name
            puts value
          else
            puts "#{field.type_name}.new!((#{storage} >> #{field.shift}) & #{mask})"
          end
        end

        return if field.const

        puts ""
        write_doc field.doc
        code_block "def", "#{field.name}=(value : #{field.type_name}) : #{field.type_name}" do
          if setter = field.setter_fun
            puts "#{library}.#{setter}(#{address}, value)"
          else
            bits = field.bool ? "value ? 1 : 0" : "value"
            puts "#{storage} = (#{storage} & ~(#{mask} << #{field.shift})) | " \
                 "((#{field.storage_type}.new!(#{bits}) & #{mask}) << #{field.shift})"
          end

          puts "value"
        end
      end

      def visit_class(klass)
        return unless write_class?(klass)

        # A Crystal class must be defined after its superclass, and after the
        # types its included modules name, like the element type of a
        # container.
        if unwritten_dependency?(klass)
          @deferred << klass
        else
          write_class(klass)
        end
      end

      # Is a wrapper for *klass* generated?
      private def write_class?(klass)
        @db.try_or(klass.origin.name, true, &.generate_wrapper?)
      end

      # Collects all classes and enums below *container* this generator will
      # write.
      private def collect_classes(container)
        container.nodes.each do |node|
          case node
          when Graph::Class
            next unless write_class?(node)
            @unwritten << node
            collect_classes(node)
          when Graph::Enum
            @unwritten << node
          when Graph::PlatformSpecific
            collect_classes(node) if node.platforms.includes? PLATFORM
          when Graph::Namespace
            collect_classes(node)
          end
        end
      end

      # Does *klass* depend on a class or enum which will be written later?
      # That's its superclass, and the types named in its included modules.
      private def unwritten_dependency?(klass)
        dependencies = [] of String
        if base = klass.base_class
          dependencies << base
        end
        klass.included_modules.each { |mod| dependencies.concat(constant_paths(mod)) }

        dependencies.any? do |path|
          node = Graph::Path.from(path).lookup(klass)
          node.is_a?(Graph::Class | Graph::Enum) && @unwritten.includes?(node)
        end
      end

      # The paths of the constants in the Crystal type *expression*, like
      # `Foo::Bar` and `Baz` in `Foo::Bar(Baz)`.
      private def constant_paths(expression : String) : Array(String)
        expression.scan(/\b(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*/).map(&.[0])
      end

      # Writes the deferred classes inside *container* whose dependencies have
      # been written in the meantime.  The containers between *container* and
      # these classes are reopened as needed, as in:
      #
      # ```
      # module N
      #   class A
      #   end
      #   # `C < B` is deferred.
      # end
      #
      # class B < N::A
      # end
      #
      # module N # Reopened
      #   class C < B
      #   end
      # end
      # ```
      private def write_deferred(container)
        reopened = [] of Graph::Container

        while klass = @deferred.find { |k| inside?(k, container) && !unwritten_dependency?(k) }
          @deferred.delete(klass)
          path = reopen_path(klass, container)

          # Close what isn't shared with the previous class, open the rest.
          common = reopened.zip?(path).take_while { |a, b| a.same?(b) }.size
          (reopened.size - common).times { close_block }
          path[common..].each { |ctr| reopen_block(ctr) }

          reopened = path
          write_class(klass)
        end

        reopened.size.times { close_block }
      end

      # Is *node* a descendant of *container*?
      private def inside?(node, container)
        parent = node.parent

        while parent
          return true if parent.same?(container)
          parent = parent.parent
        end

        false
      end

      # The containers to reopen to write *klass* in *container*, outermost
      # first.  `PlatformSpecific`s are omitted.
      private def reopen_path(klass, container)
        path = [] of Graph::Container
        parent = klass.parent

        while parent && !parent.same?(container)
          path.unshift(parent) unless parent.is_a?(Graph::PlatformSpecific)
          parent = parent.parent
        end

        path
      end

      # Reopens the already written *container*.
      private def reopen_block(container)
        if container.is_a?(Graph::Class)
          isstruct = @db.try_or(container.origin.name, false, &.kind.struct?)
          puts "#{isstruct ? "struct" : "class"} #{container.name}"
        else
          puts "module #{container.name}"
        end

        @depth += 1
      end

      # Closes a block opened by `#reopen_block`.
      private def close_block
        @depth -= 1
        puts "end"
      end

      # Writes *klass*, which must not be written before its dependencies.
      private def write_class(klass)
        @unwritten.delete(klass)

        scope = "private" if klass.origin.private?
        prefix = "abstract" if klass.abstract?
        suffix = "< #{klass.base_class}" if klass.base_class
        isstruct = @db.try_or(klass.origin.name, false, &.kind.struct?)

        write_doc klass.origin.doc
        code_block scope, prefix, isstruct ? "struct" : "class", klass.name, suffix do
          write_included_modules(klass.included_modules)
          write_instance_variables(klass.instance_variables)
          visit_children(klass)
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
        @unwritten.delete(enumeration)
        typename = Bindgen::Crystal::Typename.new(@db)
        type = Parser::Type.parse(enumeration.origin.type)
        type_name = typename.qualified(*typename.wrapper(type))

        write_doc enumeration.origin.doc
        puts "@[Flags]" if enumeration.origin.flags?
        code_block "enum", enumeration.name, ":", type_name do
          enumeration.origin.values.each do |name, value|
            puts "#{name} = #{value}"
          end
        end
      end

      def visit_method(method)
        if call = method.calls[PLATFORM]?
          write_doc method.origin.doc
          puts call.body.to_code(call, PLATFORM)
        end
      end

      # Writes the documentation comment *doc* copied from the C++ source.
      private def write_doc(doc : String?)
        return if doc.nil?

        doc.each_line do |line|
          line = line.rstrip
          puts line.empty? ? "#" : "# #{line}"
        end
      end

      def code_block(*header, &)
        puts header.reject(Nil).join(" ")
        indented { yield }
        puts "end"
      end
    end
  end
end
