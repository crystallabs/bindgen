module Bindgen
  module Processor
    # Turns OOP-y C functions into real classes.
    class FunctionClass < Base
      include Util::FindMatching(Parser::Method)

      def process(graph : Graph::Node, doc : Parser::Document)
        @config.functions.each do |regex, config|
          wrapper = config.wrapper
          next unless wrapper

          list = find_matching(regex, doc.functions)
          next if list.empty?

          handle_class(graph, config, wrapper, list)
        end
      end

      private def handle_class(root, config, wrapper, list)
        builder = Graph::Builder.new(@db)
        parent, local_name = builder.parent_and_local_name(root, Graph::Path.from(config.destination))

        klass = build_class(local_name, config, wrapper, list)

        graph_class = Graph::Class.new(
          name: local_name.camelcase,
          origin: klass,
          parent: parent,
        )

        add_type_rules(graph_class, wrapper.structure)
        add_methods(klass.methods, graph_class, wrapper.structure)
      end

      private def classify_methods(wrapper, config, list) : Array(Parser::Method)
        list.map do |method, match|
          classify_method(wrapper, config, method, match)
        end
      end

      private def classify_method(wrapper, config, method, match)
        type = detect_method_type(wrapper, method)
        arguments = method.arguments.dup

        if type.destructor? || type.member_method?
          arguments.shift # Remove self type, this'll be added later again.
        end

        function = Parser::Method.new(
          type: type,
          name: method.name,
          class_name: method.class_name,
          return_type: method.return_type,
          arguments: arguments,
          extern_c: method.extern_c?,
          doc: method.doc,
        )

        if !type.constructor? && !type.destructor?
          rewritten = Util.pattern_rewrite(config.name, match)

          if config.crystalize_names?
            function.crystal_name = function.crystal_name(override: rewritten)
          else
            function.crystal_name = rewritten.underscore
          end
        end

        function
      end

      private def detect_method_type(wrapper, method) : Parser::Method::Type
        if named_in?(wrapper.constructors, method)
          Parser::Method::Type::Constructor
        elsif (destructor = wrapper.destructor) && named_in?({destructor}, method)
          Parser::Method::Type::Destructor
        else
          if this_arg = method.arguments.first?
            if this_arg.base_name == wrapper.structure && this_arg.pointer == 1
              Parser::Method::Type::MemberMethod
            else
              Parser::Method::Type::StaticMethod
            end
          else
            Parser::Method::Type::StaticMethod
          end
        end
      end

      # Is *method* listed in *names*, by its qualified or its bare name?
      private def named_in?(names, method) : Bool
        names.includes?(method.qualified_name) || names.includes?(method.name)
      end

      private def has_default_constructor?(constructors, list)
        list.any? do |method, _|
          next unless named_in?(constructors, method)
          method.arguments.size == 0 # C doesn't support default values.
        end
      end

      private def build_baseclass(name : String)
        Parser::BaseClass.new(
          name: name,
          inherited_constructor: false,
          virtual: false,
          access: Parser::AccessSpecifier::Public,
        )
      end

      private def build_class(name, config, wrapper, list) : Parser::Class
        bases = [] of Parser::BaseClass

        if base_name = wrapper.inherit_from
          bases << build_baseclass(base_name)
        end

        Parser::Class.new(
          name: Graph::Path.from(name).last_part,
          has_default_constructor: has_default_constructor?(wrapper.constructors, list),
          has_copy_constructor: false,
          methods: classify_methods(wrapper, config, list),
          bases: bases,
        )
      end

      private def add_methods(methods : Array(Parser::Method), klass : Graph::Class, structure)
        methods.each do |method|
          add_method(method, klass, structure)
        end
      end

      private def add_method(method, klass, structure)
        wrapper = CallBuilder::CppWrapper.new(@db)
        call = CallBuilder::CppCall.new(@db)
        namer = Cpp::MethodName.new(@db)

        if method.needs_instance?
          call_method = method.dup
          call_method.arguments = method.arguments.dup
          call_method.arguments.unshift Parser::Argument.new("_self_", klass.origin.as_type)
        else
          call_method = method
        end

        graph_method = Graph::Method.new(
          origin: method,
          name: method.name,
          parent: klass,
        )

        target = call.build(
          method: call_method,
          name: namer.generate(method, "", Parser::Method::Type::StaticMethod),
        )

        graph_method.set_tag(Graph::Method::REMOVABLE_BINDING_TAG)
        graph_method.calls[Graph::Platform::Cpp] = wrapper.build(
          method: method,
          target: target,
          class_name: structure,
        )
      end

      private def add_type_rules(klass : Graph::Class, structure)
        rules = @db.get_or_add(klass.name)
        rules.crystal_type ||= klass.name
        rules.binding_type ||= structure.camelcase
        rules.cpp_type ||= structure
        rules.graph_node = klass

        @db.add_alias(structure, klass.name)
      end
    end
  end
end
