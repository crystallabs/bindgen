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

      # The document being processed, set by `#process`.
      @doc : Parser::Document?

      # Runs the processor.  You may change *graph* as you see fit.
      def process(graph : Graph::Container, doc : Parser::Document)
        @doc = doc
        visit_children(graph)
      end

      # Returns the `keep_alive:` or `depends_on:` rules, selected from the
      # type configuration by the block, applying to the methods of
      # *class_name*: its own, and those of its base classes.  A method a
      # subclass re-declares, like an override of a setter, keeps what the
      # method of the base class keeps, so the rule of the base class covers it.
      def inherited_rules(class_name : String, & : TypeDatabase::TypeConfig -> TypeDatabase::KeepAlive) : TypeDatabase::KeepAlive
        rules = TypeDatabase::KeepAlive.new
        seen = Set(String).new
        pending = [class_name]

        while name = pending.shift?
          next unless seen.add?(name)

          if config = @db[name]?
            yield(config).each { |pattern, indices| rules[pattern] = indices unless rules.has_key?(pattern) }
          end

          @doc.try(&.classes[name]?).try(&.bases.each { |base| pending << base.name })
        end

        rules
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
