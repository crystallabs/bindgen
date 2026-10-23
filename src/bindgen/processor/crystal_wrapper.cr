module Bindgen
  module Processor
    # Processor to generate a Crystal wrapper for a crystal binding.
    # `CrystalBinding` must be run beforehand.
    #
    # **Important**: This should be one of the last processors in the pipeline!
    class CrystalWrapper < Base
      include TypeHelper

      PLATFORM = Graph::Platform::Crystal

      def visit_platform_specific(specific)
        super if specific.platforms.includes?(PLATFORM)
      end

      def visit_class(klass)
        return unless @db.try_or(klass.origin.name, true, &.generate_wrapper?)
        Log.trace { "visiting class #{klass.diagnostics_path}" }
        warn_unmatched_keep_alive(klass)
        warn_unmatched_release(klass)

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

        origin = klass.origin

        if parent = klass.wrapped_class
          # If this is `Impl` class, use the pointer type of its parent.
          origin = parent.origin
        end

        # A hosted structure is copied, from a structure or a pointer to it.
        if @db.try_or(origin.name, false) { |rules| structure_hosted?(rules) }
          add_unwrap_initialize(klass, origin.as_type(pointer: 0), dereference: false)
          add_unwrap_initialize(klass, origin.as_type, dereference: true)
        else
          add_unwrap_initialize(klass, origin.as_type, dereference: false)
        end
      end

      private def add_unwrap_initialize(klass, type : Parser::Type, dereference : Bool)
        unwrap_init = CallBuilder::CrystalUnwrapInitialize.new(@db)
        unwrap_arg = Parser::Argument.new("unwrap", type)

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
        graph.calls[PLATFORM] = unwrap_init.build(method, dereference)
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

        wrapper_call = wrapper.build(method.origin, target)
        add_keep_alive_hook(wrapper_call)
        add_release_hook(wrapper_call)
        add_owner_hook(method, wrapper_call)
        wrapper_call
      end

      # Warns about the `keep_alive:` patterns of *klass* matching none of its
      # methods.
      private def warn_unmatched_keep_alive(klass)
        return unless rules = @db[klass.origin.name]?

        unmatched_patterns(klass, rules.keep_alive).each do |pattern|
          Log.warn { "keep_alive: of #{klass.origin.name} matches no method: #{pattern.source}.  Is it misspelt, or the method ignored or inherited?" }
        end
      end

      # Warns about the `release:` patterns of *klass* matching none of its
      # methods.
      private def warn_unmatched_release(klass)
        return unless rules = @db[klass.origin.name]?

        unmatched_patterns(klass, rules.release).each do |pattern|
          Log.warn { "release: of #{klass.origin.name} matches no method: #{pattern.source}.  Is it misspelt, or the method ignored or inherited?" }
        end
      end

      # Releases the object arguments of the *call*, and its object result if
      # all arguments are selected, if its class configures its method in
      # `release:`.  A post-hook: C++ handed the objects back by then.
      private def add_release_hook(call)
        method = call.origin
        return if method.any_constructor?

        rules = inherited_rules(method.class_name, &.release)
        return if rules.empty?

        indices = @db.selected_object_arguments(method, rules)
        result = @db.selects_all_arguments?(method, rules) && @db.object_type?(method.return_type)
        return if indices.empty? && !result

        body = call.body.as(Call::HookableBody)
        body.add_post_hook(ReleaseHook.new(indices, result))
      end

      # Post-hook of a wrapper method passing the arguments at *indices*, and
      # the *result*, to `BindgenHelper.release`.
      class ReleaseHook < Call::Body
        def initialize(@indices : Array(Int32), @result : Bool)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          lines = @indices.map { |index| "BindgenHelper.release(#{call.arguments[index].name})" }
          lines << "BindgenHelper.release(result)" if @result
          lines.join('\n')
        end
      end

      # Keeps the object arguments of the *call* alive, if its class configures
      # its method in `keep_alive:`.
      private def add_keep_alive_hook(call)
        indices = kept_alive_arguments(call.origin)
        return if indices.empty?

        body = call.body.as(Call::HookableBody)
        body.pre_hook = KeepAliveHook.new(indices)
      end

      # Returns the indices of the arguments of *method* to keep alive, see
      # `TypeDatabase#selected_object_arguments`, by the rules of its class and
      # the base classes (`#inherited_rules`).  A copy constructor doesn't keep
      # its argument.
      private def kept_alive_arguments(method : Parser::Method) : Array(Int32)
        return [] of Int32 if method.copy_constructor?

        rules = inherited_rules(method.class_name, &.keep_alive)
        return [] of Int32 if rules.empty?

        @db.selected_object_arguments(method, rules)
      end

      # Keeps the object of the *call* alive while the argument owning it isn't
      # `nil`, if `Processor::Qt` tagged the *method*, see
      # `Graph::Method::OWNED_BY_ARGUMENT_TAG`.  A post-hook: the object is
      # kept by the address of its C++ object, which a constructor sets first.
      private def add_owner_hook(method : Graph::Method, call)
        return unless index = method.tag?(Graph::Method::OWNED_BY_ARGUMENT_TAG)

        body = call.body.as(Call::HookableBody)
        body.add_post_hook(OwnerHook.new(index.to_i, method.origin.any_constructor?))
      end

      # Post-hook of a wrapper method keeping `self` alive while its argument at
      # *index*, the owner, isn't `nil`.  Unless in a *constructor*, `nil`
      # releases `self`, which nothing owns then.
      class OwnerHook < Call::Body
        def initialize(@index : Int32, @constructor : Bool)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          arg = call.arguments[@index]
          keep = "BindgenHelper.keep_alive(self)"

          if !arg.nilable?
            keep
          elsif @constructor
            "#{keep} if #{arg.name}"
          else
            "if #{arg.name}\n  #{keep}\nelse\n  BindgenHelper.release(self)\nend"
          end
        end
      end

      # Pre-hook of a wrapper method passing the arguments at *indices* to
      # `BindgenHelper.keep_alive`.
      class KeepAliveHook < Call::Body
        def initialize(@indices : Array(Int32))
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          @indices.join('\n') do |index|
            "BindgenHelper.keep_alive(#{call.arguments[index].name})"
          end
        end
      end

      def build_abstract_call(method)
        Log.trace { "build abstract call for #{method.diagnostics_path}" }

        builder = CallBuilder::CrystalAbstractDef.new(@db)
        builder.build(method.origin)
      end
    end
  end
end
