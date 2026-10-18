module Bindgen
  module CallBuilder
    # Builder for calls made from C++ to Crystal.  Used for callbacks, Qt
    # signals and virtual method overrides.
    class CppToCrystalProc
      def initialize(@db : TypeDatabase)
      end

      # Calls the *method*, using the *proc_name* to call-through to Crystal.
      # If *lambda* is true, instead of invoking the *method*, builds a C++
      # lambda expression that wraps the invocation.
      def build(method : Parser::Method, *, proc_name : String = "_proc_", lambda = false) : Call
        pass = Cpp::Pass.new(@db)

        # Copied structures are passed by pointer, see
        # `TypeHelper#proc_by_pointer?`.
        address = Template.from_string("&%", simple: true)
        arguments = method.arguments.map_with_index do |arg, idx|
          result = pass.passthrough_to_crystal(arg)
          if pass.proc_by_pointer?(arg)
            result = result.copy_with(conversion: result.conversion.followed_by(address))
          end
          result.to_argument(Cpp::Argument.name(arg, idx))
        end

        result = pass.to_cpp(method.return_type)
        if pass.proc_by_pointer?(method.return_type)
          deref = Template.from_string("*%", simple: true)
          result = result.copy_with(conversion: deref.followed_by(result.conversion))
        end

        Call.new(
          origin: method,
          name: proc_name,
          result: result,
          arguments: arguments,
          body: lambda ? LambdaBody.new : InvokeBody.new,
        )
      end

      # Method invocation.
      class InvokeBody < Call::Body
        def to_code(call : Call, platform : Graph::Platform) : String
          pass_args = call.arguments.map(&.call).join(", ")
          code = %[#{call.name}(#{pass_args})]
          call.result.apply_conversion(code)
        end
      end

      # Lambda expression.  Captures the `CrystalProc` by value (therefore it
      # is *not* convertible to a C function pointer).
      class LambdaBody < Call::Body
        def to_code(call : Call, platform : Graph::Platform) : String
          formatter = Cpp::Format.new

          lambda_args = formatter.argument_list(call.arguments)
          pass_args = call.arguments.map(&.call).join(", ")
          inner = %[#{call.name}(#{pass_args})]

          prefix = "return " unless call.result.type.pure_void?

          "[#{call.name}](#{lambda_args}){ #{prefix}#{inner}; }"
        end
      end
    end
  end
end
