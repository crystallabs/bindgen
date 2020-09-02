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
        def initialize(@db : TypeDatabase, @target : Call)
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
            if post
              b << encapsulate_into_variable(call, code) << "\n"
              b << post.to_code(call, platform)
              b << "result" unless call.origin.any_constructor?
            else
              b << encapsulate(call, code)
            end
          end
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          method = Crystal::Method.new(@db)
          code = @target.body.to_code(@target, platform)
          code = encapsulate_and_hook(call, platform, code)

          # Crystal doesn't like `#initialize` methods having an explicit return
          # type.
          result = call.result unless call.origin.any_constructor?

          arguments = call.arguments
          if call.name == "unsafe_fetch" && arguments.size == 1 && arguments[0].name == "index"
            idx_type = Parser::Type.builtin_type("_Int")
            idx_arg = Parser::Argument.new("index", idx_type)
            arguments = Crystal::Pass.new(@db).arguments_to_wrapper([idx_arg])
          end

          head_line = method.prototype(
            name: call.name,
            arguments: arguments,
            result: result,
            static: call.origin.static_method?,
            abstract: call.origin.pure?,
            protected: call.origin.protected?,
            private: call.origin.private?,
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
