module Bindgen
  module Processor
    # Integrates non-class functions into the graph.
    class Functions < Base
      include Util::FindMatching(Parser::Method)

      def process(graph : Graph::Node, doc : Parser::Document)
        Log.trace { "process node #{graph.diagnostics_path}" }

        # A function matched by several keys is added by the first one only
        added = Set(Parser::Method).new

        @config.functions.each do |regex, config|
          next if config.wrapper # Leave C-class functions alone

          list = find_matching(regex, doc.functions)
          list.select! { |method, _| added.add?(method) }
          next if list.empty?
          handle_functions(graph, config, list)
        end
      end

      private def handle_functions(root, config, functions)
        builder = Graph::Builder.new(@db)
        path = Graph::Path.from(config.destination)
        parent = builder.get_or_create_path(root, path).as(Graph::Container)

        functions.each do |method, match|
          add_function(parent, config, method, match)
        end
      end

      private def add_function(parent, config, method, match)
        sub_path, name = function_path_and_name(parent, config.name, match)

        Log.trace &.emit "add function", name: name, sub_path: sub_path.to_s

        if sub_path
          builder = Graph::Builder.new(@db)
          parent = builder.get_or_create_path(parent, sub_path).as(Graph::Container)
        end

        function = method.dup
        if config.crystalize_names?
          function.crystal_name = method.crystal_name(override: name)
        else
          function.crystal_name = name.underscore
        end

        Graph::Method.new(
          name: name,
          origin: function,
          parent: parent,
        )
      end

      private def function_path_and_name(base, pattern, match)
        name = Util.pattern_rewrite(pattern, match)
        path = nil

        if name.includes?("::") # Support further nesting
          parts = name.split("::")
          path_parts = parts[0..-2].map(&.camelcase)

          path = Graph::Path.from(path_parts)
          name = parts.last
        end

        {path, name}
      end
    end
  end
end
