module Bindgen
  module Processor
    # Hooks of the Crystal wrapper methods: `keep_alive:`, `release:` and the
    # parent ownership of `Processor::Qt`.  Used by `CrystalWrapper` for the
    # wrapper methods, and by `VirtualOverride` for the `Superclass`
    # forwarders, which `super` of a Crystal subclass reaches.
    module WrapperHooks
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

    end
  end
end
