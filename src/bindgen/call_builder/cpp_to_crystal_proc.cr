module Bindgen
  module CallBuilder
    # Builder for calls made from C++ to Crystal.  Used for callbacks, Qt
    # signals and virtual method overrides.
    class CppToCrystalProc
      def initialize(@db : TypeDatabase)
      end

      # Calls the *method*, using the *proc_name* to call-through to Crystal.
      # If *lambda* is true, instead of invoking the *method*, builds a C++
      # lambda expression that wraps the invocation, capturing *proc_name* by
      # value, or the *capture* given instead, like `proc = hold(f)`.
      def build(method : Parser::Method, *, proc_name : String = "_proc_", lambda = false, capture : String? = nil) : Call
        pass = Cpp::Pass.new(@db)

        # Structures are passed by pointer, see `TypeHelper#proc_by_pointer?`.
        # A converted one is a temporary, which `bindgen_address` of
        # `bindgen_helper.hpp` keeps alive for the call.
        address = Template.from_string("bindgen_address(%)", simple: true)
        outs = method.out_arguments(@db)
        arguments = method.arguments.map_with_index do |arg, idx|
          name = Cpp::Argument.name(arg, idx)
          next out_argument(pass, arg, name) if outs.includes?(idx)

          result = pass.passthrough_to_crystal(arg)
          if pass.proc_by_pointer?(arg)
            result = result.copy_with(conversion: result.conversion.followed_by(address))
          end
          result.to_argument(name)
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
          body: lambda ? LambdaBody.new(capture) : InvokeBody.new,
        )
      end

      # Builds the out argument *arg* of a call into Crystal, see
      # `Parser::Method#out_arguments`.  The `CrystalProc` takes a pointer to
      # a local of the binding type, like `CrystalString *` or `int *`, which
      # the Crystal override writes back through.  A reference, in/out, is
      # converted into the local first, and gets the local's value afterwards;
      # a pointer is out-only, gets the value if it isn't null, and the local
      # starts out value-initialized.  The locals and their write-back are the
      # `prologue` and `epilogue`, see `Cpp::Format#out_statements`.
      private def out_argument(pass : Cpp::Pass, arg : Parser::Argument, name : String) : Call::OutArgument
        value = arg.dereferenced
        to_crystal = pass.to_crystal(value)
        to_cpp = pass.to_cpp(value)
        local = Call::OutArgument.local_name(name)
        in_out = arg.reference?

        prologue = if in_out
                     "#{to_crystal.type_name} #{local} = #{to_crystal.apply_conversion(name)};"
                   else
                     "#{to_crystal.type_name} #{local}{};"
                   end

        value_back = to_cpp.apply_conversion(local)
        epilogue = in_out ? "#{name} = #{value_back};" : "if (#{name}) *#{name} = #{value_back};"

        Call::OutArgument.new(
          type: arg,
          type_name: to_crystal.type_name,
          name: name,
          call: "&#{local}",
          in_out: in_out,
          local: local,
          prologue: prologue,
          epilogue: epilogue,
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
      # is *not* convertible to a C function pointer), or whatever *capture*
      # says.
      class LambdaBody < Call::Body
        def initialize(@capture : String? = nil)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          formatter = Cpp::Format.new

          lambda_args = formatter.argument_list(call.arguments)
          pass_args = call.arguments.map(&.call).join(", ")
          inner = call.result.apply_conversion(%[#{call.name}(#{pass_args})])

          prefix = "return " unless call.result.type.pure_void?

          "[#{@capture || call.name}](#{lambda_args}){ #{prefix}#{inner}; }"
        end
      end
    end
  end
end
