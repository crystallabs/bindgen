module Bindgen
  module Processor
    # A processor setting up copied macro definitions.
    class Macros < Base
      include Util::FindMatching(Parser::Macro)

      # Default value for `Configuration::Macro#type` for an enumeration
      ENUM_DEFAULT_TYPE = "int"

      def process(graph : Graph::Node, doc : Parser::Document)
        @config.macros.each do |regex, config|
          list = find_matching(regex, doc.macros)
          handle_macros(graph, config, list)
        end
      end

      private def handle_macros(root, config, macros)
        case config.map_as
        when .enum?
          create_enum(root, config, macros)
        when .constant?
          create_constants(root, config, macros)
        else
          raise "BUG: Missing case in #handle_macros"
        end
      end

      # Adds the enum described in *config* to the graph, using *macros* as
      # values.
      private def create_enum(root, config, macros)
        builder = Graph::Builder.new(@db)
        path = Graph::Path.from(config.destination)

        # Traverse, create missing namespaces on the way.
        parent, local_name = builder.parent_and_local_name(root, path)

        Graph::Enum.new(
          name: local_name,
          parent: parent,
          origin: build_enum(config, macros, local_name),
        )
      end

      # Adds all *macros* into the graph.
      private def create_constants(root, config, macros)
        type = Crystal::Type.new(@db)
        builder = Graph::Builder.new(@db)
        path = Graph::Path.from(config.destination)
        parent = builder.get_or_create_path(root, path).as(Graph::Container)
        host = parent.platform_specific(Graph::Platform::Crystal)

        if type_name = config.type # Force to user configured type
          forced_type = Parser::Type.parse(type_name)
        end

        macros.each do |define, match|
          next if define.function?
          name = Util.pattern_rewrite(config.name, match).underscore.upcase
          # Without a type the macro couldn't be evaluated: Nothing to copy.
          next unless value_type = forced_type || define.type
          value = type.convert(define.evaluated, value_type)

          next if value.nil?

          Graph::Constant.new(
            name: name,
            value: value,
            parent: host,
          )
        end
      end

      # Builds an enumeration type out of *config* and *macros*.
      private def build_enum(config, macros, name) : Parser::Enum
        values = {} of String => Int64

        macros.each do |define, match|
          enumerator = Util.pattern_rewrite(config.name, match).downcase.camelcase
          value = define.evaluated

          unless value.is_a? Int
            raise "Macro enum #{config.destination}: " \
                  "Value for #define #{define.name} is non-Int: #{value.inspect}"
          end

          values[enumerator] = value.to_i64
        end

        Parser::Enum.new(
          name: name,
          values: values,
          type: (config.type || ENUM_DEFAULT_TYPE),
          flags: config.flags,
        )
      end
    end
  end
end
