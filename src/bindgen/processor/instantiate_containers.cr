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

      # Module for pairs
      PAIR_MODULE = "BindgenHelper::PairContainer"

      # Module for optionals
      OPTIONAL_MODULE = "BindgenHelper::OptionalContainer"

      # The parsed document, for container instantiations listed in `classes:`.
      @doc : Parser::Document?

      def process(graph : Graph::Node, doc : Parser::Document)
        root = graph.as(Graph::Container)
        @doc = doc

        @config.containers.each { |container| resolve_instantiations(container) }
        add_nested_instantiations

        # Containers like `std::vector` and `std::__1::vector` share a module.
        used = @config.containers.reject(&.instantiations.empty?)
        used.group_by { |container| module_name(container.class) }.each_value do |containers|
          build_container_module(containers, root)
        end

        # Pairs first: Their type rules are needed by the containers of them.
        pairs, others = @config.containers.partition(&.type.pair?)
        (pairs + others).each do |container|
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
        when .pair?
          add_pair_containers(container, root)
        when .optional?
          add_optional_containers(container, root)
        else
          raise "BUG: Missing case for #{container.type.inspect}"
        end
      end

      # Adds all instances of the sequential *container* into *root*.
      private def add_sequential_containers(container, root)
        nested_first(container.instantiations).each do |instance|
          check_sequential_instance! container, instance
          add_sequential_container(container, instance, root)
        end
      end

      # Adds all instances of the associative *container* into *root*.
      private def add_associative_containers(container, root)
        nested_first(container.instantiations).each do |instance|
          check_associative_instance! container, instance
          add_associative_container(container, instance, root)
        end
      end

      # Adds all instances of the *container* pair type into *root*.
      private def add_pair_containers(container, root)
        nested_first(container.instantiations).each do |instance|
          check_associative_instance! container, instance
          add_pair_container(container, instance, root)
        end
      end

      # Adds all instances of the optional *container* into *root*.
      private def add_optional_containers(container, root)
        nested_first(container.instantiations).each do |instance|
          check_sequential_instance! container, instance
          add_optional_container(container, instance, root)
        end
      end

      # Instantiates a single optional *container* *instance* into *root*.
      # Like a pair's, its wrapper is an implementation detail: The type rules
      # convert an optional to and from a `T?`.
      private def add_optional_container(container, instance, root)
        builder = Graph::Builder.new(@db)

        templ_type = Parser::Type.parse(cpp_container_name(container, instance))
        templ_args = templ_type.template_arguments
        klass = build_optional_class(container, templ_type)

        if parsed_class(templ_type)
          raise "#{templ_type.full_name} is listed in `classes:`, but wrapping the methods of an optional isn't supported"
        end

        add_cpp_typedef(root, templ_type, klass.name)
        set_container_type_rules(container, templ_type, klass.name, klass.name)

        graph = builder.build_class(klass, klass.name, root)
        graph.set_tag(Graph::Class::FORCE_UNWRAP_VARIABLE_TAG)
        graph.included_modules << container_module(OPTIONAL_MODULE, templ_args)
        graph.included_modules << container_module(container.class, templ_args)
        @db.get_or_add(templ_type.full_name).graph_node = graph
      end

      # Instantiates a single pair *container* *instance* into *root*.  Its
      # wrapper is an implementation detail: The type rules convert a pair to
      # and from a Crystal `Tuple`.
      private def add_pair_container(container, instance, root)
        builder = Graph::Builder.new(@db)

        templ_type = Parser::Type.parse(cpp_container_name(container, instance))
        templ_args = templ_type.template_arguments
        klass = build_pair_class(container, templ_type)

        if parsed_class(templ_type)
          raise "#{templ_type.full_name} is listed in `classes:`, but wrapping the methods of a pair isn't supported"
        end

        add_cpp_typedef(root, templ_type, klass.name)
        set_container_type_rules(container, templ_type, klass.name, klass.name)

        graph = builder.build_class(klass, klass.name, root)
        graph.set_tag(Graph::Class::FORCE_UNWRAP_VARIABLE_TAG)
        graph.included_modules << container_module(PAIR_MODULE, templ_args)
        graph.included_modules << container_module(container.class, templ_args)
        @db.get_or_add(templ_type.full_name).graph_node = graph
      end

      # The *instantiations* with the less nested ones first, so the rules of
      # a nested container exist when the one of it is instantiated.
      private def nested_first(instantiations)
        instantiations.to_a.sort_by { |instance| instance.sum(&.count('<')) }
      end

      # Instantiates the containers nested in the arguments of the configured
      # instantiations, like the `std::vector<int>` of
      # `std::vector<std::vector<int>>`, which `AutoContainerInstantiation`
      # does for the ones it finds in methods.
      private def add_nested_instantiations
        loop do
          added = false

          @config.containers.each do |container|
            container.instantiations.dup.each do |instance|
              instance.each do |arg|
                templ = Parser::Type.parse(arg).template
                next unless templ
                nested = @config.containers.find(&.class.== templ.base_name)
                next unless nested
                arg_count = nested.type.pair? || nested.type.associative? ? 2 : 1
                next if templ.arguments.size < arg_count

                instantiation = templ.arguments[0...arg_count].map { |t| @db.resolve_aliases(t).full_name }
                added = true if nested.instantiations.add?(instantiation)
              end
            end
          end

          break unless added
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
      #
      # An instantiation listed in `classes:` was parsed, so its wrapper gets
      # the methods and bases of the C++ class, under the configured name, on
      # top of the container methods.
      private def add_sequential_container(container, instance, root)
        builder = Graph::Builder.new(@db)

        templ_type = Parser::Type.parse(cpp_container_name(container, instance))
        templ_args = templ_type.template_arguments
        cpp_name = container_class_name(templ_type)

        if parsed = parsed_class(templ_type)
          klass = adopt_parsed_class(container, parsed, templ_type, cpp_name)
          crystal_name = @db[templ_type.full_name]?.try(&.crystal_type) || cpp_name
        else
          klass = build_sequential_class(container, templ_type)
          crystal_name = cpp_name
        end

        add_cpp_typedef(root, templ_type, cpp_name)
        set_container_type_rules(container, templ_type, cpp_name, crystal_name)

        graph = builder.build_class(klass, crystal_name, root)
        graph.set_tag(Graph::Class::FORCE_UNWRAP_VARIABLE_TAG)
        graph.included_modules << container_module(SEQUENTIAL_MODULE, templ_args)
        graph.included_modules << container_module(container.class, templ_args)

        # A class deriving from the instantiation finds its base through this.
        @db.get_or_add(templ_type.full_name).graph_node = graph
      end

      # The parsed class of the instantiation *templ_type*, if it was listed
      # in `classes:`.
      private def parsed_class(templ_type) : Parser::Class?
        @doc.try(&.classes[templ_type.full_name]?)
      end

      # Turns the *parsed* instantiation of the sequential *container* into a
      # container class: The container methods are added, replacing the C++
      # ones of the same name, so the wrapper's `Indexable` implementation
      # doesn't depend on how they are declared.  The constructors are replaced
      # by the default constructor of the C++ typedef *cpp_name*, like other
      # containers have: The type rules of the instantiation copy a returned
      # instance, which a constructor's result must not be.  `.from` builds a
      # container from any `Enumerable`.  The other methods are filtered like
      # `FilterMethods` does, as that ran before this class existed.
      private def adopt_parsed_class(container, parsed : Parser::Class, templ_type, cpp_name : String) : Parser::Class
        var_type = templ_type.template_arguments.first
        container_methods = {container.access_method, container.push_method, container.size_method}
        filter = FilterMethods.new(@config, @db)
        parsed.methods.reject! do |m|
          m.any_constructor? || container_methods.includes?(m.name) || filter.filtered?(m)
        end

        parsed.methods << default_constructor_method(Parser::Class.new(name: cpp_name))
        parsed.methods << access_method(container, parsed.name, var_type)
        parsed.methods << push_method(container, parsed.name, var_type)
        parsed.methods << size_method(container, parsed.name)

        parsed
      end

      # Instantiates a single associative *container* *instance* into *root*.
      # The entries of the container are copied for iteration into a
      # `BindgenMapEntries`, which is wrapped as the nested `Entries` class.
      private def add_associative_container(container, instance, root)
        builder = Graph::Builder.new(@db)

        templ_type = Parser::Type.parse(cpp_container_name(container, instance))
        templ_args = templ_type.template_arguments
        klass = build_associative_class(container, templ_type)
        entries = build_entries_class(klass, templ_type)
        entries_type = Parser::Type.parse("BindgenMapEntries<#{templ_type.full_name}>")

        if parsed_class(templ_type)
          raise "#{templ_type.full_name} is listed in `classes:`, but wrapping the methods of an associative container isn't supported"
        end

        add_cpp_typedef(root, templ_type, klass.name)
        add_cpp_typedef(root, entries_type, entries.name)
        set_container_type_rules(container, templ_type, klass.name, klass.name)

        graph = builder.build_class(klass, klass.name, root)
        graph.set_tag(Graph::Class::FORCE_UNWRAP_VARIABLE_TAG)
        graph.included_modules << container_module(ASSOCIATIVE_MODULE, templ_args)
        graph.included_modules << container_module(container.class, templ_args)
        @db.get_or_add(templ_type.full_name).graph_node = graph

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

      # Updates the rules of the *container* instantiated as *templ_type*, whose
      # C++ typedef is *cpp_name* and whose wrapper class is *crystal_name*.
      # The rules are changed to convert from and to the binding type.  The
      # wrapper takes and returns the `Enumerable` of the container module,
      # also if the instantiation is listed in `classes:` under another name.
      private def set_container_type_rules(container, templ_type, cpp_name : String, crystal_name : String)
        rules = @db.get_or_add(templ_type.full_name)
        type_args = templ_type.template_arguments

        rules.pass_by = TypeDatabase::PassBy::Pointer
        rules.wrapper_pass_by = TypeDatabase::PassBy::Value
        rules.binding_type = cpp_name
        rules.crystal_type = enumerable_type(container, type_args)
        rules.container_type ||= container_module(container.class, type_args)
        rules.cpp_type ||= cpp_name

        if rules.to_crystal.no_op?
          to_crystal = case container.type
                       when .pair?     then "#{crystal_name}.new(unwrap: %).to_tuple"
                       when .optional? then "#{crystal_name}.new(unwrap: %).to_nilable"
                       else                 "#{crystal_name}.new(unwrap: %)"
                       end
          rules.to_crystal = Template.from_string(to_crystal, simple: true)
        end
        if rules.from_crystal.no_op?
          from_crystal = case container.type
                         when .pair?, .optional? then "#{crystal_name}.from(%).to_unsafe"
                         else                         "BindgenHelper.wrap_container(#{crystal_name}, %).to_unsafe"
                         end
          rules.from_crystal = Template.from_string(from_crystal, simple: true)
        end
        if rules.from_cpp.no_op?
          rules.from_cpp = Template.from_string(@db.cookbook.value_to_pointer(cpp_name))
        end
        if rules.to_cpp.no_op?
          rules.to_cpp = Template.from_string(@db.cookbook.pointer_to_reference(cpp_name))
        end

        # We can no longer mark a template specialization as an alias of another
        # type, so we cheat by making both types share the same binding type
        # (this is normally not an issue since all binding types are `Void`).
        rules = @db.get_or_add(cpp_name)
        rules.binding_type = cpp_name
      end

      # Returns the Crystal type of the *container* instantiated with the
      # *type_args*: The `Enumerable` the wrapper includes, where associative
      # containers enumerate tuples of the key and the value, like `Hash`, the
      # `Tuple` a pair converts to, or the `T?` an optional converts to.
      private def enumerable_type(container, type_args)
        case container.type
        when .associative? then "Enumerable({#{wrapper_type_list(type_args)}})"
        when .pair?        then "Tuple(#{wrapper_type_list(type_args)})"
        when .optional?    then "#{wrapper_type_list(type_args)}?"
        else                    container_module("Enumerable", type_args)
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
        var_type = templ_type.template_arguments.first
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
        key_type, value_type = templ_type.template_arguments
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
          [Parser::Argument.new("map", self_type), key_arg], value_type.never_nil)

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

      # Builds a full `Parser::Class` for the pair *container* in the specified
      # *instantiation*.  The members are reached through the helper functions
      # `bindgen_pair_first`, `bindgen_pair_second` and `bindgen_pair_set` of
      # `bindgen_helper.hpp`, as they are fields, not methods.
      private def build_pair_class(container, templ_type : Parser::Type) : Parser::Class
        first_type, second_type = templ_type.template_arguments
        klass = container_class(container, templ_type)
        # The typedef, which Crystal knows as the wrapper class: The pair type
        # itself converts to a `Tuple`.
        self_type = Parser::Type.parse("#{klass.name} &")
        pair_arg = Parser::Argument.new("pair", self_type)
        first_arg = Parser::Argument.new("first", first_type)
        second_arg = Parser::Argument.new("second", second_type)

        klass.methods << default_constructor_method(klass)
        klass.methods << map_helper_method(klass, "bindgen_pair_first", "first", [pair_arg], first_type.never_nil)
        klass.methods << map_helper_method(klass, "bindgen_pair_second", "second", [pair_arg], second_type.never_nil)
        klass.methods << map_helper_method(klass, "bindgen_pair_set", "set",
          [pair_arg, first_arg, second_arg], Parser::Type::VOID)

        klass
      end

      # Builds a full `Parser::Class` for the optional *container* in the
      # specified *instantiation*: `has_value`, `value` and `emplace`, which
      # `BindgenHelper::OptionalContainer` uses.
      private def build_optional_class(container, templ_type : Parser::Type) : Parser::Class
        var_type = templ_type.template_arguments.first
        klass = container_class(container, templ_type)

        klass.methods << default_constructor_method(klass)

        klass.methods << Parser::Method.build(
          name: container.count_method,
          class_name: klass.name,
          arguments: [] of Parser::Argument,
          return_type: Parser::Type.builtin_type("bool"),
          crystal_name: "unsafe_has_value",
        )

        klass.methods << Parser::Method.build(
          name: container.access_method,
          class_name: klass.name,
          arguments: [] of Parser::Argument,
          return_type: var_type.never_nil,
          crystal_name: "unsafe_value",
        )

        klass.methods << Parser::Method.build(
          name: container.push_method,
          class_name: klass.name,
          arguments: [Parser::Argument.new("value", var_type)],
          return_type: Parser::Type::VOID,
          crystal_name: "unsafe_emplace",
        )

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
        key_type, value_type = templ_type.template_arguments
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
          return_type: key_type.never_nil,
          crystal_name: "unsafe_key",
        )

        entries.methods << Parser::Method.build(
          name: "value",
          class_name: entries.name,
          arguments: [index_arg],
          return_type: value_type.never_nil,
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
        Parser::Class.new(name: container_class_name(templ_type), has_default_constructor: true)
      end

      # The name of the C++ typedef of the instantiation *templ_type*, and of
      # its wrapper class unless `classes:` names it.
      private def container_class_name(templ_type : Parser::Type) : String
        "Container_#{templ_type.mangled_name}"
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
          return_type: var_type.never_nil, # `Indexable(T)` returns a `T`
          crystal_name: "unsafe_at",       # Used by `SequentialContainer#unsafe_fetch`
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
