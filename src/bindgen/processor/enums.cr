module Bindgen
  module Processor
    # Adds enumerations to the graph.
    class Enums < Base
      def process(graph : Graph::Node, doc : Parser::Document)
        doc.enums.each do |name, enumeration|
          if enumeration.anonymous?
            config = Configuration::Enum.new(
              destination: enumeration.name,
            )
          else
            config = @config.enums[name]
          end

          add_enum(graph, config, enumeration)
        end
      end

      # Adds *enumeration* according to *config* into the *root*.
      private def add_enum(root, config, enumeration)
        origin = reconfigure_enum(config, enumeration)

        if origin.anonymous?
          # Re-parent the anonumous enum if the enclosing class is wrapped.
          path = Graph::Path.from(config.destination)
          if parent = @db[path.parent.to_s]?
            if parent.generate_wrapper? && (wrapper_name = parent.wrapper_type)
              path = Graph::Path.from(wrapper_name, path.last_part)
            end
          end

          emit_enum(origin, path, root)
        else
          builder = Graph::Builder.new(@db)
          builder.build_enum(origin, config.destination, root)
        end
      end

      # Reconfigures *enumeration* according to the users *config*.
      private def reconfigure_enum(config, enumeration : Parser::Enum) : Parser::Enum
        is_flags = config.flags.get(enumeration.flags?)
        fields = remove_key_prefix(config.prefix, enumeration.values)

        Parser::Enum.new(
          name: enumeration.name,
          type: enumeration.type, # Make configurable?
          flags: is_flags,
          anonymous: enumeration.anonymous?,
          values: camelcase_fields(config, fields),
          doc: enumeration.doc,
        )
      end

      # Writes the enumerators of the given *enumeration* to the *destination*
      # path relative to *root*.
      private def emit_enum(enumeration, destination, root)
        builder = Graph::Builder.new(@db)
        type = Crystal::Type.new(@db)

        # Enums aren't copied in C++ but constants are, and we don't need them
        # in C++.
        path = Graph::Path.from(destination)
        parent, _ = builder.parent_and_local_name(root, path)
        host = parent.platform_specific(Graph::Platform::Crystal)
        value_type = Parser::Type.parse(enumeration.type)

        enumeration.values.each do |name, value|
          if typed_value = type.convert(value, value_type)
            Graph::Constant.new(
              parent: host,
              name: name.underscore.upcase,
              value: typed_value,
            )
          end
        end
      end

      # CamelCases all field names, if they're not already camel-cased.
      private def camelcase_fields(config, fields)
        fields.map do |key, value|
          if config.camelcase
            unless key[0]?.try(&.uppercase?) && key[1]?.try(&.lowercase?)
              key = key.downcase.camelcase
            end
          elsif key[0]?.try(&.lowercase?)
            key = key[0].upcase + key[1..]
          end

          {key, value}
        end.to_h
      end

      # Removes the common *prefix* from all *fields*.  If *prefix* is `true`,
      # finds the common prefix of *fields* automatically.
      private def remove_key_prefix(prefix : String | Bool, fields)
        return fix_constant_names(fields) if prefix == false

        if prefix == true # Auto prefix detection
          prefix = Util::Prefix.common(fields.keys)
          return fields if prefix == 0
        end

        remove_hash_key_prefix(prefix.as(Int32 | String), fields)
      end

      # Removes the first *prefix* characters from each key in *hash*.
      private def remove_hash_key_prefix(prefix : Int32, hash)
        transform_keys_unique(hash) do |key|
          key[prefix..-1]
        end
      end

      # Removes the *prefix* of each key in *hash*, but only for those key
      # starting with *prefix*.
      private def remove_hash_key_prefix(prefix : String, hash)
        transform_keys_unique(hash) do |key|
          if key.starts_with?(prefix)
            key[prefix.size..-1]
          else
            key
          end
        end
      end

      # Yields all keys in *hash* and returns a new hash with the yield
      # returned new keys.  Keys are tracked to make sure they're unique.
      # Keys are afterwards sent through `#fixed_constant_name`.
      private def transform_keys_unique(hash : Hash(K, _), &) forall K
        seen = Hash(K, Int32).new(default_value: 0)

        hash.map do |key, value|
          key = fixed_constant_name(yield(key))

          count = (seen[key] += 1)
          key = "#{key}_#{count}" if count > 1 # Make sure keys are unique

          {key, value}
        end.to_h
      end

      private def fixed_constant_name(key : String) : String
        if key.empty?
          "Unnamed"
        elsif key[0].number?
          "Digit#{key}"
        elsif key[0] == '_'
          "Underscore#{key[1..-1]}"
        else
          key
        end
      end

      # Maps the keys in *hash* using `#fixed_constant_name`.
      private def fix_constant_names(hash)
        # Will fix the name by itself.
        transform_keys_unique(hash, &.itself)
      end
    end
  end
end
