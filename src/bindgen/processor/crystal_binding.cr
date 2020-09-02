module Bindgen
  module Processor
    # Processor to write `lib` bindings to the functions created by the
    # `CppWrapper` processor.
    class CrystalBinding < Base
      PLATFORM = Graph::Platform::CrystalBinding

      # A `Call::Result` pointing to a `Void` result.
      VOID_RESULT = Call::Result.new(
        type: Parser::Type::VOID,
        type_name: "Void",
        reference: false,
        pointer: 0,
        nilable: false,
      )

      # Late-initialized in `#process`
      @binding : Graph::Library?

      def initialize(_config, db)
        super
        @builder = CallBuilder::CrystalBinding.new(db)
        @aliases = {} of String => Graph::Node
      end

      def process(graph : Graph::Container, _doc : Parser::Document)
        binding = graph.by_name(Graph::LIB_BINDING).as(Graph::Library)
        @binding = binding

        super

        # Prepend aliases.  Swap the whole thing, else we'd be `#unshift`ing
        # every single alias, which (with many funs and aliases) can get slow
        # real fast.
        nodes = binding.nodes.dup
        binding.nodes.replace(@aliases.values)
        binding.nodes.concat nodes

        @aliases.each_value do |node|
          node.parent = binding # Fix up the nodes `parent`
        end
      end

      def visit_platform_specific(specific)
        return unless specific.platforms.includes? PLATFORM
        super
      end

      def visit_library(library)
        nil # We're already in a `lib`, so ignore inner libraries.
      end

      def visit_class(klass)
        return unless @db.try_or(klass.origin.name, true, &.generate_binding)

        # We want a Void alias for *all* classes.
        pass = Crystal::Pass.new(@db)
        add_type_alias pass.to_binding(klass.origin.as_type, qualified: false)

        super
      end

      def visit_method(method)
        # Allow previous processors to supply custom calls instead.
        call = method.calls[PLATFORM]?

        if call.nil?
          call = add_and_get_call(method)
          method.calls[PLATFORM] = call
        end

        # Insert call into the `lib Binding`
        binding_method = Graph::Method.new(
          parent: @binding,
          name: method.name,
          origin: method.origin,
        )

        binding_method.calls[PLATFORM] = call
        binding_method.tags.merge!(method.tags)

        add_type_aliases(call)
      end

      # Creates a `fun` `Call` of *method* to automatically bind to C++ methods.
      private def add_and_get_call(method)
        if klass = method.parent_class
          klass_type = klass.origin.as_type
        end

        explicit_bind = method.tag?(Graph::Method::EXPLICIT_BIND_TAG)

        @builder.build(
          method: method.origin,
          klass_type: klass_type,
          explicit_binding: explicit_bind,
        )
      end

      # Makes sure all types in *call* are have an alias to `Void`.
      private def add_type_aliases(call)
        add_type_alias call.result
        call.arguments.each { |arg| add_type_alias(arg) }
      end

      # Adds an `alias` for *expr* into the known aliases list.
      private def add_type_alias(expr : Call::Expression)
        type = expr.type

        return if type.builtin? || type.void? # Built-ins don't need aliases
        return if @aliases.has_key? expr.type_name
        if rules = @db[type]?
          return if rules.builtin
          return if rules.ignore
          return if rules.copy_structure
          return if rules.kind.enum?
          return if rules.graph_node.is_a?(Graph::Enum)
        end

        @aliases[expr.type_name] = Graph::Alias.new( # `alias EXPR_NAME = Void`
origin: VOID_RESULT,
          name: expr.type_name,
          parent: nil,
        )
      end
    end
  end
end
