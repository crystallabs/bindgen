module Bindgen
  module CallBuilder
    # Builds a `Call` implementing a common method calling a `CrystalBinding`
    # call.
    class CrystalWrapper
      def initialize(@db : TypeDatabase)
      end

      def build(method : Parser::Method, target : Call)
        pass = Crystal::Pass.new(@db)

        arguments = pass.arguments_to_wrapper(method.arguments)
        if method.any_constructor?
          body = ConstructorBody.new(@db, target)
        else
          body = MethodBody.new(@db, target)
        end

        Call.new(
          origin: method,
          name: method.crystal_name,
          arguments: arguments,
          result: pass.from_wrapper(method.return_type, method.any_constructor?),
          body: body,
        )
      end

      abstract class Body < Call::HookableBody
        # Does the method forward to `#superclass` on an instance of a Crystal
        # subclass?  Set by `Processor::VirtualOverride` for the virtual
        # methods with a `Superclass` forwarder: a Crystal subclass, which the
        # `BindgenWrapper` annotation of the generated classes tells apart,
        # reaches the wrapper method by `super`, or by not overriding it, so
        # Crystal's dispatch ran its overrides already.  Calling the C++
        # implementation under the shadow class then, instead of the virtual
        # method, doesn't re-enter the override: `super` works.
        property super_forwarder = false

        def initialize(@db : TypeDatabase, @target : Call)
        end

        # The forwarding to `#superclass`, see `#super_forwarder`.  Only a
        # subclass of a class with a `Superclass` wrapper, whose wrapper has
        # the method (`superclass_ignore_methods` may leave it out), forwards.
        private def superclass_forwarding(call) : String
          args = call.arguments.map(&.name).join(", ")

          %[{% unless @type.annotation(BindgenWrapper) %}\n] \
          %[  {% if @type.has_method?("superclass") %}\n] \
          %[    if (_superclass_ = superclass).responds_to?(:#{call.name})\n] \
          %[      return _superclass_.#{call.name}(#{args})\n] \
          %[    end\n] \
          %[  {% end %}\n] \
          %[{% end %}\n]
        end

        # Generates the call itself.
        abstract def encapsulate(call, code)

        def encapsulate_into_variable(call, code)
          "result = " + encapsulate(call, code)
        end

        # Support for pre- and post hooks.
        private def encapsulate_and_hook(call, platform, code)
          pre = @pre_hook
          post = @post_hook

          String.build do |b|
            b << pre.to_code(call, platform) << "\n" if pre
            if post && !call.origin.any_constructor? && !call.origin.has_result?
              # Nothing to return: The `Void` method returns `nil` after the hook.
              b << encapsulate(call, code) << "\n"
              b << post.to_code(call, platform)
            elsif post
              b << encapsulate_into_variable(call, code) << "\n"
              b << post.to_code(call, platform)
              b << "\nresult" unless call.origin.any_constructor?
            else
              b << encapsulate(call, code)
            end
          end
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          method = Crystal::Method.new(@db)
          code = @target.body.to_code(@target, platform)
          code = encapsulate_and_hook(call, platform, code)
          code = superclass_forwarding(call) + code if @super_forwarder

          # Crystal doesn't like `#initialize` methods having an explicit return
          # type.
          result = call.result unless call.origin.any_constructor?

          head_line = method.prototype(
            name: call.name,
            arguments: call.arguments,
            result: result,
            static: call.origin.static?,
            abstract: call.origin.pure?,
            protected: call.origin.protected?,
            private: call.origin.private?,
            named_args: call.origin.aggregate_constructor?,
          )

          %[#{head_line}\n] \
          %[  #{code}\n] \
          %[end\n]
        end
      end

      class MethodBody < Body
        def encapsulate(call, code)
          call.result.apply_conversion(code)
        end
      end

      class ConstructorBody < Body
        def encapsulate_into_variable(call, code)
          encapsulate(call, code)
        end

        def encapsulate(call, code)
          %[result = #{code}\n] \
          %[@unwrap = result]
        end
      end
    end
  end
end
