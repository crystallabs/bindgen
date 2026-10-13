module Bindgen
  module Generator
    # Generator for Crystal `lib`.  Automatically invoked by `Crystal`.
    class CrystalLib < Base
      include Graph::Visitor

      PLATFORM = Graph::Platform::CrystalBinding

      def write(node : Graph::Container)
        raise "CrystalLib#write_all expects a Graph::Library" unless node.is_a?(Graph::Library)

        visit_node(node)
      end

      def visit_library(library)
        puts %<@[Link(ldflags: "#{library.ld_flags}")]> if library.ld_flags
        puts "lib #{library.name}"
        indented { super }
        puts "end"
      end

      def visit_class(klass)
        return unless @db.try_or(klass.origin.name, true, &.generate_binding?)
        super
      end

      def visit_method(method)
        call = method.calls[PLATFORM]?
        return if call.nil? # Ignore non-bound methods
        puts call.body.to_code(call, PLATFORM)
      end

      def visit_struct(structure)
        write_structure(structure, false)
      end

      def visit_union(structure)
        write_structure(structure, true)
      end

      private def write_structure(structure, cpp_union : Bool)
        puts "#{cpp_union ? "union" : "struct"} #{structure.name}"
        indented do
          structure.fields.each do |name, result|
            # can't use Void as a struct field type directly
            ptr = result.pointer
            ptr = {ptr, 1}.max if result.type_name == "Void"

            if result.type.c_array?
              # Crystal's `Int32[2][3][4]` is really equivalent to C's
              # `int [4][3][2]`, so the extents have to be reversed when they
              # are written to a `lib`.
              extents = result.type.extents.reverse
              subscripts = extents.join { |v| "[#{v}]" }
              ptr -= extents.size
            end

            stars = "*" * ptr if ptr > 0

            puts "#{name} : #{result.type_name}#{stars}#{subscripts}"
          end
        end
        puts "end"
      end

      def visit_alias(alias_name)
        puts "alias #{alias_name.name} = #{alias_name.origin.type_name}"
      end
    end
  end
end
