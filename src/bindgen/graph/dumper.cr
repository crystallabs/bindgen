module Bindgen
  module Graph
    # Dumps a graph for diagnostic purposes.  See `.dump`.
    class Dumper
      include Visitor

      # Single-depth indention
      INDENTION = "  "

      # Indention depth
      @depth = 0

      def initialize(@io : IO)
      end

      # Dumps *node*, and all of its children, into *io*.
      def self.dump(io : IO, node : Node)
        new(io).visit_node(node)
      end

      def visit_platform_specific(specific)
        puts node_header(specific)
        indented { super }
      end

      def visit_alias(alias_name)
        puts "#{node_header(alias_name)} -> #{alias_name.origin.type_name}"
      end

      def visit_constant(constant)
        puts "#{node_header(constant)} = #{constant.value.inspect}"
      end

      def visit_class(klass)
        puts node_header(klass)
        indented { super }
      end

      def visit_enum(enumeration)
        suffix = " @[Flags]" if enumeration.origin.flags?

        puts "#{node_header(enumeration)} (#{enumeration.origin.values.size} constants)#{suffix}"
        super
      end

      def visit_library(library)
        puts node_header(library)
        indented { super }
      end

      def visit_method(method)
        args = method.origin.arguments.map { |arg| "#{arg.full_name} #{arg.name}" }.join(", ")
        puts "#{node_header(method)}(#{args}) : #{method.origin.return_type.full_name}"

        indented do
          method.calls.each do |platform, call|
            puts call_to_s(platform, call)
          end
        end

        super
      end

      # Returns a dump-able string for the *call* on *platform*
      private def call_to_s(platform, call)
        args = call.arguments.map { |arg| "#{arg.type_name} #{arg.name}" }.join(", ")
        "#{platform}: #{call.name}(#{args}) : #{call.result.type_name}"
      end

      def visit_namespace(ns)
        puts node_header(ns)
        indented { super }
      end

      def visit_struct(structure)
        puts node_header(structure)
        super
      end

      # The generic header string of *node*
      private def node_header(node : Node) : String
        "#{node.kind_name}: #{node.name}"
      end

      # Increments `@depth`, yields, and decrements `@depth` afterwards again.
      private def indented(&)
        @depth += 1
        yield
      ensure
        @depth -= 1
      end

      # Writes *str* into the `@io`, adhering to the current indention depth.
      private def puts(str : String)
        prefix = INDENTION * @depth
        data = prefix + str.gsub("\n", "\n#{prefix}")
        @io.puts data
      end
    end
  end
end
