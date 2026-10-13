module Bindgen
  module Processor
    # Generates a class for each to-be instantiated container type.
    # This processor must be run *before* any processor that generates platform
    # specific `Call`s, like `Crystal` or `Cpp`.
    class InstantiateContainers < Base
      # Name of the "standard" built-in integer C++ type.  Required for the
      # generated `#size` method, and `#unsafe_fetch` of sequential containers.
      CPP_INTEGER_TYPE = "int"

      # Module for sequential containers
      SEQUENTIAL_MODULE = "BindgenHelper::SequentialContainer"

      # Module for associative containers
      ASSOCIATIVE_MODULE = "BindgenHelper::AssociativeContainer"

      def process(graph : Graph::Node, _doc : Parser::Document)
        root = graph.as(Graph::Container)

        @config.containers.each do |container|
          build_container_module(container, root)
          instantiate_container(container, root)
        end
      end

      # Builds the wrapper module under *root* for the given *container*.  The
      # module is responsible for naming instantiated container wrappers.
      private def build_container_module(container, root)
        sizes = container.instantiations.map(&.size)
        unless sizes.uniq.size == 1
          raise "All instantiations of #{container.class} must have the same number of arguments"
        end
        arg_count = sizes.first

        formal_args = arg_count == 1 ? %w[T] : Array(String).new(arg_count) { |i| "T#{i + 1}" }
        crystal_name = "#{container.class}(#{formal_args.join(", ")})"
        path = Graph::Path.from(crystal_name, generic: true).camelcase

        builder = Graph::Builder.new(@db)
        parent = builder.get_or_create_path(root, path).as(Graph::Container)
        call = CallBuilder::CrystalContainerOf.new(@db)

        macro_method = of_macro(container)
        macro_node = Graph::Method.new(
          origin: macro_method,
          name: macro_method.name,
          parent: parent.platform_specific(Graph::Platform::Crystal),
        )
        macro_node.calls[Graph::Platform::Crystal] = call.build(macro_method, container)
      end

      # Instantiates the *container* (Of any type), placing the built classes
      # into *root*.
      private def instantiate_container(container, root)
        logger.trace { "instantiate container #{container.class}" }

        case container.type
        when .sequential?
          add_sequential_containers(container, root)
        when .associative?
          raise "Associative containers are not yet supported."
        else
          raise "BUG: Missing case for #{container.type.inspect}"
        end
      end

      # Adds all instances of the sequential *container* into *root*.
      private def add_sequential_containers(container, root)
        resolve_instantiations(container).each do |instance|
          check_sequential_instance! container, instance
          add_sequential_container(container, instance, root)
        end
      end

      # Resolves aliases in the type arguments of *container*'s instantiations.
      # This is required because aliases from the config files are not resolved
      # prior to this point.
      private def resolve_instantiations(container)
        container.instantiations.map do |inst|
          inst.map { |t| @db.resolve_aliases(t).full_name }
        end.uniq
      end

      # Instantiates a single *container* *instance* into *root*.
      private def add_sequential_container(container, instance, root)
        builder = Graph::Builder.new(@db)

        templ_type = Parser::Type.parse(cpp_container_name(container, instance))
        templ_args = templ_type.template.not_nil!.arguments
        klass = build_sequential_class(container, templ_type)

        add_cpp_typedef(root, templ_type, klass.name)
        set_sequential_container_type_rules(container, klass, templ_type)

        graph = builder.build_class(klass, klass.name, root)
        graph.set_tag(Graph::Class::FORCE_UNWRAP_VARIABLE_TAG)
        graph.included_modules << container_module(SEQUENTIAL_MODULE, templ_args)
        graph.included_modules << container_module(container.class, templ_args)
      end

      # Generates the C++ template name of a container class.
      private def cpp_container_name(container, instance)
        typer = Cpp::Typename.new
        typer.template_class(container.class, instance)
      end

      # Generates the Crystal module name of a container class.
      private def container_module(kind, types)
        pass = Crystal::Pass.new(@db)
        typer = Crystal::Typename.new(@db)
        args = types.map { |t| typer.full pass.to_wrapper(t) }.join(", ")

        "#{Graph::Path.from(kind).camelcase}(#{args})"
      end

      # Adds a `typedef Container<T...> Container_T...` for C++.
      private def add_cpp_typedef(root, type, cpp_type_name)
        # On top for C++!
        host = Graph::PlatformSpecific.new(platform: Graph::Platform::Cpp)
        root.nodes.unshift host
        host.parent = root

        origin = Call::Result.new(
          type: type,
          type_name: type.full_name,
          reference: false,
          pointer: 0,
        )

        Graph::Alias.new(
          # Build the `typedef`.
          origin: origin,
          name: cpp_type_name,
          parent: host,
        )
      end

      # Updates the rules of the sequential *container* *klass*, whose
      # instantiated type is *templ_type*.  The rules are changed to convert
      # from and to the binding type.
      private def set_sequential_container_type_rules(container, klass : Parser::Class, templ_type)
        rules = @db.get_or_add(templ_type.full_name)
        type_args = templ_type.template.not_nil!.arguments

        rules.pass_by = TypeDatabase::PassBy::Pointer
        rules.wrapper_pass_by = TypeDatabase::PassBy::Value
        rules.binding_type = klass.name
        rules.crystal_type ||= container_module("Enumerable", type_args)
        rules.container_type ||= container_module(container.class, type_args)
        rules.cpp_type ||= klass.name

        if rules.to_crystal.no_op?
          rules.to_crystal = Template.from_string(
            "#{klass.name}.new(unwrap: %)", simple: true)
        end
        if rules.from_crystal.no_op?
          rules.from_crystal = Template.from_string(
            "BindgenHelper.wrap_container(#{klass.name}, %).to_unsafe", simple: true)
        end
        if rules.from_cpp.no_op?
          rules.from_cpp = Template.from_string(@db.cookbook.value_to_pointer(klass.name))
        end
        if rules.to_cpp.no_op?
          rules.to_cpp = Template.from_string(@db.cookbook.pointer_to_reference(klass.name))
        end

        # We can no longer mark a template specialization as an alias of another
        # type, so we cheat by making both types share the same binding type
        # (this is normally not an issue since all binding types are `Void`).
        rules = @db.get_or_add(klass.as_type)
        rules.binding_type = klass.name
      end

      # Checks if *instance* of *container* is valid.  If not, raises.
      private def check_sequential_instance!(container, instance)
        if instance.size != 1
          raise "Container #{container.class} was expected to have exactly one template argument"
        end
      end

      # Builds a full `Parser::Class` for the sequential *container* in the
      # specified *instantiation*.
      private def build_sequential_class(container, templ_type : Parser::Type) : Parser::Class
        var_type = templ_type.template.not_nil!.arguments.first
        klass = container_class(container, templ_type)

        klass.methods << default_constructor_method(klass)
        klass.methods << access_method(container, klass.name, var_type)
        klass.methods << push_method(container, klass.name, var_type)
        klass.methods << size_method(container, klass.name)

        klass
      end

      # Takes a `Configuration::Container` and returns a `Parser::Class` for a
      # specific *instantiation*.
      #
      # Note: The returned class doesn't include any modules.  This is done on
      # the `Graph::Class` of the Crystal wrapper, see `#container_module`.
      private def container_class(container, templ_type : Parser::Type) : Parser::Class
        name = "Container_#{templ_type.mangled_name}"
        Parser::Class.new(name: name, has_default_constructor: true)
      end

      # Builds a method defining a default constructor for *klass*.
      private def default_constructor_method(klass : Parser::Class)
        Parser::Method.build(
          type: Parser::Method::Type::Constructor,
          class_name: klass.name,
          name: "",
          return_type: klass.as_type,
          arguments: [] of Parser::Argument,
        )
      end

      # Builds the access method for the *klass_name* of a instantiated container.
      private def access_method(container : Configuration::Container, klass_name : String, var_type : Parser::Type) : Parser::Method
        idx_type = Parser::Type.builtin_type(CPP_INTEGER_TYPE)
        idx_arg = Parser::Argument.new("index", idx_type)

        Parser::Method.build(
          name: container.access_method,
          class_name: klass_name,
          arguments: [idx_arg],
          return_type: var_type,
          crystal_name: "unsafe_fetch", # Will implement `Indexable#unsafe_fetch`
        )
      end

      # Builds the push method for the *klass_name* of a instantiated container.
      private def push_method(container : Configuration::Container, klass_name : String, var_type : Parser::Type) : Parser::Method
        var_arg = Parser::Argument.new("value", var_type)
        Parser::Method.build(
          name: container.push_method,
          class_name: klass_name,
          arguments: [var_arg],
          return_type: Parser::Type::VOID,
          crystal_name: "push",
        )
      end

      # Builds the size method for the *klass_name* of a instantiated container.
      private def size_method(container : Configuration::Container, klass_name : String) : Parser::Method
        Parser::Method.build(
          name: container.size_method,
          class_name: klass_name,
          arguments: [] of Parser::Argument,
          return_type: Parser::Type.builtin_type(CPP_INTEGER_TYPE),
          crystal_name: "size", # `Indexable#size`
        )
      end

      # Builds the `.of` macro of the given *container* module.
      private def of_macro(container)
        Parser::Method.build(
          type: Parser::Method::Type::Macro,
          class_name: container.class,
          name: "of",
          return_type: Parser::Type::EMPTY,
          arguments: [] of Parser::Argument,
        )
      end
    end
  end
end
