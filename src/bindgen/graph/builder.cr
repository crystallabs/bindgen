module Bindgen
  module Graph
    # Builds a graph out of `Parser::*` structures.  Can be used to build a
    # whole namespace out of a `Parser::Document`, or just for smaller things.
    #
    # The resulting graph mirrors the structure of the target language.
    class Builder
      def initialize(@db : TypeDatabase)
      end

      # Copies *document* into the *ns*.
      def build_document(document : Parser::Document, ns : Namespace) : Namespace
        document.classes.each do |_, klass|
          target_name = @db[klass.name].crystal_type || klass.name.camelcase
          build_class(klass, target_name, ns)
        end

        ns # Done!
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

        # Add all (in theory) wrappable methods
        klass.wrap_methods.each do |method|
          build_method(method, graph_class)
        end

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

      # ditto
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
