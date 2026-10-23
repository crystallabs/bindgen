module Bindgen
  module Graph
    # Builds a graph out of `Parser::*` structures.  Can be used to build a
    # whole namespace out of a `Parser::Document`, or just for smaller things.
    #
    # The resulting graph mirrors the structure of the target language.
    class Builder
      def initialize(@db : TypeDatabase)
      end

      # Copies *document* into the *ns*.  The classes named in *except* are
      # left out, like container instantiations `Processor::InstantiateContainers`
      # builds.
      def build_document(document : Parser::Document, ns : Namespace, except = Set(String).new) : Namespace
        document.classes.each do |_, klass|
          next if except.includes?(klass.name)
          target_name = crystal_path(klass.name, document)

          if @db[klass.name]?.nil? && klass.anonymous?
            enclosing_type = klass.name.gsub(/::[^:]+$/, "")

            @db.add(klass.name,
              crystal_type: target_name,
              binding_type: klass.name,
              copy_structure: @db.try_or(enclosing_type, false, &.copy_structure?),
              bit_fields: @db.try_or(enclosing_type, TypeDatabase::BitFields::Accessors, &.bit_fields),
              generate_binding: false,
              generate_wrapper: false,
            )
          end

          build_class(klass, target_name, ns)
        end

        ns # Done!
      end

      # Crystal path of the class *name*.  An anonymous class is nested in its
      # enclosing class, which may have been renamed.
      private def crystal_path(name : String, document : Parser::Document) : String
        if crystal_type = @db[name]?.try(&.crystal_type)
          crystal_type
        elsif document.classes[name]?.try(&.anonymous?)
          enclosing, _, local_name = name.rpartition("::")
          "#{crystal_path(enclosing, document)}::#{local_name.camelcase}"
        else
          name.camelcase
        end
      end

      # Copies *klass* at path *name* into the *root*.
      def build_class(klass : Parser::Class, name : String, root : Graph::Container) : Graph::Class
        parent, local_name = parent_and_local_name(root, name)

        # Create the class itself
        graph_class = Graph::Class.new(
          parent: parent,
          name: local_name,
          origin: klass,
        )

        # Add all (in theory) wrappable methods, and those declared in the
        # configuration, see the `declare_methods:` type rule.
        rules = @db[klass.name]?
        rules.try &.declare_methods.each do |signature|
          klass.methods << Parser::Method.from_signature(signature, klass.name)
        end

        # In place: processors copying the methods into subclasses see it.
        methods = klass.wrap_methods
        methods.reject! { |method| @db.shadowed_overload?(method, methods) }

        methods.each do |method|
          apply_method_rules(method, rules) if rules
          build_method(method, graph_class)
        end
        warn_unmatched_method_rules(klass, rules) if rules

        # Store graph node in the type database
        @db.get_or_add(klass.name).graph_node = graph_class
        graph_class
      end

      # Copies *enumeration* at path *name* into the *root*.
      def build_enum(enumeration : Parser::Enum, name : String, root : Graph::Container) : Graph::Enum
        parent, local_name = parent_and_local_name(root, name)

        graph_enum = Graph::Enum.new(
          parent: parent,
          name: local_name,
          origin: enumeration,
        )

        # Store graph node in the type database
        @db.get_or_add(enumeration.name).graph_node = graph_enum
        graph_enum
      end

      # Applies the `rename:` and `nilable:` *rules* of its class to the
      # *method*, in place: processors copying it into subclasses and
      # `Superclass` wrappers see the changes.
      private def apply_method_rules(method : Parser::Method, rules : TypeDatabase::TypeConfig)
        if name = rules.rename_for(method)
          method.crystal_name = name
        end

        unless (nilable = rules.nilable_result?(method)).nil?
          if nilable_pointer?(method.return_type)
            method.return_type = method.return_type.with_nilable(nilable)
          else
            Log.warn { "nilable: of #{method.class_name} ignores #{method.name}: its result isn't a pointer" }
          end
        end

        rules.nilable_arguments(method).each do |index|
          if (arg = method.arguments[index]?) && nilable_pointer?(arg)
            method.arguments[index] = arg.with_nilable(true)
          else
            Log.warn { "nilable: of #{method.class_name} ignores argument #{index} of #{method.name}: it isn't a pointer" }
          end
        end
      end

      # Can *type*, a single pointer to a wrapped class, be `nil`?
      private def nilable_pointer?(type : Parser::Type) : Bool
        type.pointer == 1 && !type.reference? && !type.move? && !type.c_array? &&
          @db.try_or(type, false) { |rules| rules.kind.class? && !rules.copy_structure? }
      end

      # Warns about the `rename:` and `nilable:` patterns of *klass* matching
      # none of its methods.
      private def warn_unmatched_method_rules(klass : Parser::Class, rules : TypeDatabase::TypeConfig)
        methods = klass.wrap_methods
        (rules.rename.keys + rules.nilable.keys).each do |pattern|
          unless methods.any? { |method| pattern.matches?(method) }
            Log.warn { "rename: or nilable: of #{klass.name} matches no method: #{pattern}.  Is it misspelt, or the method ignored or inherited?" }
          end
        end
      end

      # Copies *method* into *parent*.
      def build_method(method : Parser::Method, parent : Graph::Node?) : Graph::Method
        Graph::Method.new(
          origin: method,
          name: method.name,
          parent: parent,
        )
      end

      # Splits the qualified *path*, and returns the parent of the target
      # and the name of the *path* local to the parent.
      def parent_and_local_name(root : Graph::Container, path_name : String)
        parent_and_local_name(root, Path.from(path_name))
      end

      # :ditto:
      def parent_and_local_name(root : Graph::Container, path : Path)
        parent = get_or_create_path_parent(root, path)
        {parent, path.last_part}
      end

      # Gets the parent of *path*, starting at *root*.  Makes sure it is a
      # `Graph::Container`.  Also see `#get_or_create_path`
      def get_or_create_path_parent(root : Graph::Container, path : Path) : Graph::Container
        parent = get_or_create_path(root, path.parent)

        unless parent.is_a?(Graph::Container)
          raise "Expected a container (module or class) at #{path}, but got a #{parent.class} instead"
        end

        parent
      end

      # Iterates over the *path*, descending from *root* onwards.  If a part of
      # the path does not exist yet, it'll be created as `Namespace`.
      def get_or_create_path(root : Graph::Container, path : Path) : Graph::Node
        if path.global? || path.self_path?
          return root
        end

        path.parts.reduce(root) do |ctr, name|
          unless ctr.is_a?(Graph::Container)
            raise "Path #{path.inspect} is illegal, as #{name.inspect} is not a container"
          end

          parent = ctr.nodes.find(&.name.== name)
          if parent.nil? # Create a new module if it doesn't exist.
            parent = Graph::Namespace.new(name: name, parent: ctr)
          end

          parent
        end
      end
    end
  end
end
