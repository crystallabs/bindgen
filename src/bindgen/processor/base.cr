module Bindgen
  module Processor
    # Base-class for all processors.
    #
    # The processor `Runner` will instantiate all processors first, then call
    # `#process` in order as configured.
    #
    # All processors are automatically made available as their
    # `String#underscore`d name through in the `processors` configuration.
    #
    # If your processor only requires to act on specific graph nodes, you can
    # simply override the corresponding `#visit_X` method.  See `FilterMethods`
    # for an example of this.
    abstract class Base
      macro inherited
        Log = ::Log.for(self)
      end

      include Graph::Visitor

      def initialize(@config : Configuration, @db : TypeDatabase)
      end

      # Runs the processor.  You may change *graph* as you see fit.
      def process(graph : Graph::Container, doc : Parser::Document)
        visit_children(graph)
      end

      # Returns the patterns of *rules*, the `keep_alive:` or `depends_on:`
      # configuration of *klass*, matching the name of none of its methods, so
      # a typo, or a pattern for an ignored method, isn't silent.  Only the
      # methods the class declares count, those bound from a superclass follow
      # the rules of the superclass.
      def unmatched_patterns(klass : Graph::Class, rules : TypeDatabase::KeepAlive) : Array(Regex)
        return [] of Regex if rules.empty?

        names = Set(String).new
        collect_method_names(klass, klass.origin.name, names)
        rules.keys.reject { |pattern| names.any? { |name| pattern.matches?(name) } }
      end

      # Adds the names of the methods of *class_name* in *container*, and in
      # its platform-specific parts, to *names*.
      private def collect_method_names(container : Graph::Container, class_name : String, names : Set(String))
        container.nodes.each do |node|
          case node
          when Graph::Method
            names << node.origin.name if node.origin.class_name == class_name
          when Graph::PlatformSpecific
            collect_method_names(node, class_name, names)
          end
        end
      end
    end
  end
end
