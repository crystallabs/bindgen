module Bindgen
  module Processor
    # Generates a class for each to-be instantiated container type.
    # This processor must be run *before* any processor that generates platform
    # specific `Call`s, like `Crystal` or `Cpp`.
    class InstantiateContainers < Base
      # Name of the "standard" built-in integer C++ type.  Required for the
      # generated `#size` method, and `#unsafe_at` of sequential containers.
      CPP_INTEGER_TYPE = "int"

      # Module for sequential containers
      SEQUENTIAL_MODULE = "BindgenHelper::SequentialContainer"

      # Module for associative containers
      ASSOCIATIVE_MODULE = "BindgenHelper::AssociativeContainer"

      def process(graph : Graph::Node, _doc : Parser::Document)
        root = graph.as(Graph::Container)

        @config.containers.each { |container| resolve_instantiations(container) }

        # Containers like `std::vector` and `std::__1::vector` share a module.
        used = @config.containers.reject(&.instantiations.empty?)
        used.group_by { |container| module_name(container.class) }.each_value do |containers|
          build_container_module(containers, root)
        end

        @config.containers.each do |container|
          instantiate_container(container, root)
        end
      end

      # Builds the wrapper module under *root* shared by the given *containers*.
      # The module is responsible for naming instantiated container wrappers.
      private def build_container_module(containers, root)
        container = containers.first

        sizes = containers.flat_map(&.instantiations.map(&.size))
        unless sizes.uniq.size == 1
          raise "All instantiations of #{containers.map(&.class).join(", ")} must have the same number of arguments"
        end
        arg_count = sizes.first

        formal_args = arg_count == 1 ? %w[T] : Array(String).new(arg_count) { |i| "T#{i + 1}" }
        crystal_name = "#{module_name(container.class)}(#{formal_args.join(", ")})"
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
        macro_node.calls[Graph::Platform::Crystal] = call.build(macro_method, containers)
      end

      # Instantiates the *container* (Of any type), placing the built classes
      # into *root*.
      private def instantiate_container(container, root)
        Log.trace { "instantiate container #{container.class}" }

        case container.type
        when .sequential?
          add_sequential_containers(container, root)
        when .associative?
          add_associative_containers(container, root)
        else
          raise "BUG: Missing case for #{container.type.inspect}"
        end
      end

      # Adds all instances of the sequential *container* into *root*.
      private def add_sequential_containers(container, root)
        container.instantiations.each do |instance|
          check_sequential_instance! container, instance
          add_sequential_container(container, instance, root)
        end
      end

      # Adds all instances of the associative *container* into *root*.
      private def add_associative_containers(container, root)
        container.instantiations.each do |instance|
          check_associative_instance! container, instance
          add_associative_container(container, instance, root)
        end
      end

      # Resolves aliases in the type arguments of *container*'s instantiations,
      # as those from the config files are not resolved prior to this point.
      # Instantiations which only differ in the spelling of their arguments,
      # like `std::vector<rgb>` and `std::vector<unsigned int>`, are merged
      # into one.
      private def resolve_instantiations(container)
        resolved = container.instantiations.map do |inst|
          inst.map { |t| @db.resolve_aliases(t).full_name }
        end

        container.instantiations = resolved.to_set
      end

      # Instantiates a single *container* *instance* into *root*.
      private def add_sequential_container(container, instance, root)
        builder = Graph::Builder.new(@db)

        templ_type = Parser::Type.parse(cpp_container_name(container, instance))
        templ_args = templ_type.template.not_nil!.arguments
        klass = build_sequential_class(container, templ_type)

        add_cpp_typedef(root, templ_type, klass.name)
        set_container_type_rules(container, klass, templ_type)

        graph = builder.build_class(klass, klass.name, root)
        graph.set_tag(Graph::Class::FORCE_UNWRAP_VARIABLE_TAG)
        graph.included_modules << container_module(SEQUENTIAL_MODULE, templ_args)
        graph.included_modules << container_module(container.class, templ_args)
      end

      # Instantiates a single associative *container* *instance* into *root*.
      # The entries of the container are copied for iteration into a
      # `BindgenMapEntries`, which is wrapped as the nested `Entries` class.
      private def add_associative_container(container, instance, root)
        builder = Graph::Builder.new(@db)

        templ_type = Parser::Type.parse(cpp_container_name(container, instance))
        templ_args = templ_type.template.not_nil!.arguments
        klass = build_associative_class(container, templ_type)
        entries = build_entries_class(klass, templ_type)
        entries_type = Parser::Type.parse("BindgenMapEntries<#{templ_type.full_name}>")

        add_cpp_typedef(root, templ_type, klass.name)
        add_cpp_typedef(root, entries_type, entries.name)
        set_container_type_rules(container, klass, templ_type)

        graph = builder.build_class(klass, klass.name, root)
        graph.set_tag(Graph::Class::FORCE_UNWRAP_VARIABLE_TAG)
        graph.included_modules << container_module(ASSOCIATIVE_MODULE, templ_args)
        graph.included_modules << container_module(container.class, templ_args)

        entries_graph = builder.build_class(entries, "Entries", graph)
        entries_graph.set_tag(Graph::Class::FORCE_UNWRAP_VARIABLE_TAG)
      end

      # Generates the C++ template name of a container class.
      private def cpp_container_name(container, instance)
        typer = Cpp::Typename.new
        typer.template_class(container.class, instance)
      end

      # Generates the Crystal module name of a container class.
      private def container_module(kind, types)
        "#{Graph::Path.from(module_name(kind)).camelcase}(#{wrapper_type_list(types)})"
      end

      # Returns the comma-separated Crystal wrapper types of *types*.
      private def wrapper_type_list(types)
        pass = Crystal::Pass.new(@db)
        typer = Crystal::Typename.new(@db)
        types.map { |t| typer.full pass.to_wrapper(t) }.join(", ")
      end

      # Removes implementation namespaces like `__1` in `std::__1::vector` from
      # *name*, as they don't map to a valid Crystal constant.
      private def module_name(name : String) : String
        name.split("::").reject(&.starts_with?("__")).join("::")
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

      # Updates the rules of the *container* *klass*, whose instantiated type is
      # *templ_type*.  The rules are changed to convert from and to the binding
      # type.
      private def set_container_type_rules(container, klass : Parser::Class, templ_type)
        rules = @db.get_or_add(templ_type.full_name)
        type_args = templ_type.template.not_nil!.arguments

        rules.pass_by = TypeDatabase::PassBy::Pointer
        rules.wrapper_pass_by = TypeDatabase::PassBy::Value
        rules.binding_type = klass.name
        rules.crystal_type ||= enumerable_type(container, type_args)
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

      # Returns the `Enumerable` the wrapper of *container* instantiated with
      # the *type_args* includes.  Associative containers enumerate tuples of
      # the key and the value, like `Hash`.
      private def enumerable_type(container, type_args)
        if container.type.associative?
          "Enumerable({#{wrapper_type_list(type_args)}})"
        else
          container_module("Enumerable", type_args)
        end
      end

      # Checks if *instance* of *container* is valid.  If not, raises.
      private def check_associative_instance!(container, instance)
        if instance.size != 2
          raise "Container #{container.class} was expected to have exactly two template arguments"
        end
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

      # Builds a full `Parser::Class` for the associative *container* in the
      # specified *instantiation*.  Lookups and assignments use the helper
      # functions `bindgen_map_fetch` and `bindgen_map_store`, as `at()` throws
      # and `operator[]` requires a default constructible value type.
      private def build_associative_class(container, templ_type : Parser::Type) : Parser::Class
        key_type, value_type = templ_type.template.not_nil!.arguments
        klass = container_class(container, templ_type)
        self_type = Parser::Type.parse("#{templ_type.full_name} &")
        key_arg = Parser::Argument.new("key", key_type)
        value_arg = Parser::Argument.new("value", value_type)

        klass.methods << default_constructor_method(klass)
        klass.methods << size_method(container, klass.name)

        klass.methods << Parser::Method.build(
          name: container.count_method,
          class_name: klass.name,
          arguments: [key_arg],
          return_type: Parser::Type.builtin_type(CPP_INTEGER_TYPE),
          crystal_name: "unsafe_count", # Used by `AssociativeContainer#has_key?`
        )

        klass.methods << Parser::Method.build(
          name: container.erase_method,
          class_name: klass.name,
          arguments: [key_arg],
          return_type: Parser::Type::VOID,
          crystal_name: "unsafe_erase", # Used by `AssociativeContainer#delete`
        )

        klass.methods << map_helper_method(klass, "bindgen_map_fetch", "fetch",
          [Parser::Argument.new("map", self_type), key_arg], value_type)

        if insert_method = container.insert_method
          klass.methods << Parser::Method.build(
            name: insert_method,
            class_name: klass.name,
            arguments: [key_arg, value_arg],
            return_type: Parser::Type::VOID,
            crystal_name: "unsafe_store", # Used by `AssociativeContainer#[]=`
          )
        else
          klass.methods << map_helper_method(klass, "bindgen_map_store", "store",
            [Parser::Argument.new("map", self_type), key_arg, value_arg], Parser::Type::VOID)
        end

        klass
      end

      # Builds a static method of *klass* calling the global helper function
      # *name* from `bindgen_helper.hpp`.  Its Crystal name is `unsafe_` and
      # the *suffix*.
      private def map_helper_method(klass, name, suffix, arguments, return_type)
        method = Parser::Method.build(
          type: Parser::Method::Type::StaticMethod,
          name: name,
          class_name: Cpp::MethodName::GLOBAL_SCOPE,
          arguments: arguments,
          return_type: return_type,
          crystal_name: "unsafe_#{suffix}",
        )

        # Name the binding after the container, as the helper is global.
        method.binding_name = "#{klass.name}_#{suffix}"
        method
      end

      # Builds the class of the `BindgenMapEntries` of the associative
      # container *klass*, whose instantiated type is *templ_type*.
      private def build_entries_class(klass, templ_type : Parser::Type) : Parser::Class
        key_type, value_type = templ_type.template.not_nil!.arguments
        entries = Parser::Class.new(name: "#{klass.name}_Entries")
        map_type = Parser::Type.parse("const #{templ_type.full_name} &")
        index_arg = Parser::Argument.new("index", Parser::Type.builtin_type(CPP_INTEGER_TYPE))

        entries.methods << Parser::Method.build(
          type: Parser::Method::Type::Constructor,
          class_name: entries.name,
          name: "",
          return_type: entries.as_type,
          arguments: [Parser::Argument.new("map", map_type)],
        )

        entries.methods << size_method_named("size", entries.name)

        entries.methods << Parser::Method.build(
          name: "key",
          class_name: entries.name,
          arguments: [index_arg],
          return_type: key_type,
          crystal_name: "unsafe_key",
        )

        entries.methods << Parser::Method.build(
          name: "value",
          class_name: entries.name,
          arguments: [index_arg],
          return_type: value_type,
          crystal_name: "unsafe_value",
        )

        entries
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
          crystal_name: "unsafe_at", # Used by `SequentialContainer#unsafe_fetch`
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
        size_method_named(container.size_method, klass_name)
      end

      # Builds the size method called *name* for the *klass_name*.
      private def size_method_named(name : String, klass_name : String) : Parser::Method
        Parser::Method.build(
          name: name,
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
