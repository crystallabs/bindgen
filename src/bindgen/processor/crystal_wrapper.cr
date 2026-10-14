module Bindgen
  module Processor
    # Processor to generate a Crystal wrapper for a crystal binding.
    # `CrystalBinding` must be run beforehand.
    #
    # **Important**: This should be one of the last processors in the pipeline!
    class CrystalWrapper < Base
      PLATFORM = Graph::Platform::Crystal

      def visit_platform_specific(specific)
        super if specific.platforms.includes?(PLATFORM)
      end

      def visit_class(klass)
        return unless @db.try_or(klass.origin.name, true, &.generate_wrapper?)
        Log.trace { "visiting class #{klass.diagnostics_path}" }

        # The parent class already has the `@unwrap`
        if klass.base_class.nil? || klass.tag?(Graph::Class::FORCE_UNWRAP_VARIABLE_TAG)
          unwrap = add_unwrap_variable(klass)
          add_to_unsafe_method(klass, unwrap)
        end

        add_unwrap_initialize(klass)

        super
      end

      private def add_unwrap_variable(klass) : Call::Result
        Log.trace { "add_unwrap_variable #{klass.diagnostics_path}" }

        typer = Crystal::Typename.new(@db)

        if structure = klass.structure
          type = klass.origin.as_type(pointer: 0)
          type_name = Graph::Path.local(from: klass, to: structure).to_s
        else
          type = klass.origin.as_type(pointer: 1)
          type_name = typer.qualified(*typer.binding(type))
        end

        klass.instance_variables["unwrap"] ||= Call::Result.new(
          type: type,
          type_name: type_name,
          pointer: type.pointer,
          reference: false,
        )
      end

      private def add_to_unsafe_method(klass, unwrap)
        Log.trace { "add_to_unsafe_method #{klass.diagnostics_path}" }

        to_unsafe = CallBuilder::CrystalToUnsafe.new(@db)
        isstruct = @db.try_or(klass.origin.name, false, &.kind.struct?)
        call = to_unsafe.build(klass.origin, unwrap.pointer < 1 && !isstruct)

        host = klass.platform_specific(PLATFORM)

        graph = Graph::Method.new(origin: call.origin, name: call.name, parent: host)

        Log.trace &.emit "add to unsafe method", diagnostics_path: graph.diagnostics_path, origin: call.origin.name, name: call.name

        graph.calls[PLATFORM] = call
      end

      private def add_unwrap_initialize(klass)
        Log.trace { "add_unwrap_initialize #{klass.diagnostics_path}" }

        unwrap_init = CallBuilder::CrystalUnwrapInitialize.new(@db)
        origin = klass.origin

        if parent = klass.wrapped_class
          # If this is `Impl` class, use the pointer type of its parent.
          origin = parent.origin
        end

        unwrap_arg = Parser::Argument.new("unwrap", origin.as_type)

        method = Parser::Method.build(
          type: Parser::Method::Type::Constructor,
          name: "",
          class_name: klass.name,
          return_type: Parser::Type::EMPTY,
          arguments: [unwrap_arg],
        )

        Log.trace &.emit "add unwrap_initialize", class_name: klass.name, crystal_name: method.crystal_name

        host = klass.platform_specific(PLATFORM)
        graph = Graph::Method.new(origin: method, name: method.name, parent: host)
        graph.set_tag(Graph::Method::UNWRAP_INITIALIZE_TAG)
        graph.calls[PLATFORM] = unwrap_init.build(method)
      end

      def visit_method(method)
        return if method.calls[PLATFORM]?

        Log.trace { "visiting method #{method.diagnostics_path}" }

        if method.origin.pure?
          call = build_abstract_call(method)
        else
          call = build_method_call(method)
        end

        method.calls[PLATFORM] = call
      end

      def build_method_call(method)
        Log.trace { "build method call for #{method.diagnostics_path}" }

        klass_type = nil
        if (klass = method.parent).is_a?(Graph::Class)
          klass_type = klass.origin.as_type
        end

        call = CallBuilder::CrystalBinding.new(@db)
        wrapper = CallBuilder::CrystalWrapper.new(@db)
        target = call.build(method.origin, klass_type, CallBuilder::CrystalBinding::InvokeBody)

        wrapper.build(method.origin, target)
      end

      def build_abstract_call(method)
        Log.trace { "build abstract call for #{method.diagnostics_path}" }

        builder = CallBuilder::CrystalAbstractDef.new(@db)
        builder.build(method.origin)
      end
    end
  end
end
