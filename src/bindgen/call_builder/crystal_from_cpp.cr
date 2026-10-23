module Bindgen
  module CallBuilder
    # Builder for calls made from C++ to a Crystal `CrystalProc`.
    #
    # The `Proc` runs the call in `BindgenHelper.rescued`: an exception it
    # raises goes to `BindgenHelper.on_exception`, and a zero of the result
    # type returns to C++, as the exception can't unwind through C++ frames.
    class CrystalFromCpp
      def initialize(@db : TypeDatabase)
      end

      # Calls the *method*, using the *proc_name* to call-through to Crystal.
      #
      # If `do_block` is true, the generated `Proc` expression will use
      # `do ... end` instead of `{ ... }`.  This allows embedding the code body
      # inside a string conversion template, without the code block being
      # interpreted as an environment variable (see also `Template::Basic`).
      def build(method : Parser::Method, receiver = "self", do_block = false) : Call
        pass = Crystal::Pass.new(@db)
        argument = Crystal::Argument.new(@db)

        outs = method.out_arguments(@db)
        arguments = method.arguments.map_with_index do |arg, idx|
          name = argument.name(arg, idx)
          next out_argument(pass, arg, name) if outs.includes?(idx)

          caller = pass.from_binding(arg, qualified: true)
          callee = pass.from_wrapper(arg, callback_argument: true)
          result = combine_result(caller, callee)
          result = pointer_argument(result) if pass.proc_by_pointer?(arg)
          result.to_argument(name)
        end

        callee = pass.to_wrapper(method.return_type)
        caller = pass.to_binding(method.return_type, to_unsafe: true, qualified: true)
        result = combine_result(caller, callee)
        by_pointer = pass.proc_by_pointer?(method.return_type)
        result = pointer_result(result) if by_pointer

        Call.new(
          origin: method,
          name: method.crystal_name,
          result: result,
          arguments: arguments,
          body: Body.new(@db, receiver, do_block, fallback(result, by_pointer)),
        )
      end

      # Builds the out argument *arg* of the `Proc`, see
      # `Parser::Method#out_arguments`: C++ passes a pointer to the binding
      # type, like `Binding::CrystalString*` or `Int32*`.  The override takes
      # the value of an in/out argument, a reference, and returns the values of
      # all out arguments in its tuple, see `Crystal::Pass#wrapper_result`,
      # which `Body` writes back through the pointers: the `epilogue`.
      private def out_argument(pass : Crystal::Pass, arg : Parser::Argument, name : String) : Call::OutArgument
        value = arg.dereferenced
        caller = pass.from_binding(value, qualified: true)
        callee = pass.from_wrapper(value, callback_argument: true)
        result = combine_result(caller, callee)
        back = pass.to_binding(value, to_unsafe: true, qualified: true)
        local = Call::OutArgument.local_name(name)

        Call::OutArgument.new(
          type: arg,
          type_name: result.type_name,
          name: name,
          call: result.apply_conversion("#{name}.value"),
          in_out: arg.reference?,
          local: local,
          epilogue: "#{name}.value = #{back.apply_conversion(local)}",
          pointer: result.pointer + 1,
        )
      end

      # The value the `Proc` returns to C++ if the call raised: `nil` for
      # nothing, a zeroed copy for a structure returned *by_pointer*, else the
      # zero of the *result* type.
      private def fallback(result : Call::Result, by_pointer : Bool) : String
        return "nil" if result.type.pure_void?

        typer = Crystal::Typename.new(@db)
        type_name = typer.full(result, expects_type: false)

        if by_pointer
          "#{type_name}.malloc(1)"
        elsif result.pointer > 0
          "#{type_name}.null"
        else
          "BindgenHelper.zero_value(#{type_name})"
        end
      end

      # Combines the results *outer* to *inner*.
      private def combine_result(outer, inner)
        combined_conversion = inner.conversion.followed_by(outer.conversion)

        Call::Result.new(
          type: outer.type,
          type_name: outer.type_name,
          pointer: outer.pointer,
          reference: outer.reference,
          conversion: combined_conversion,
        )
      end

      # Receives a copied structure by pointer, see
      # `TypeHelper#proc_by_pointer?`.
      private def pointer_argument(result)
        value = Template.from_string("%.value", simple: true)
        result.copy_with(
          pointer: 1, reference: false,
          conversion: value.followed_by(result.conversion),
        )
      end

      # Returns a copied structure by pointer to a copy allocated by the GC.
      private def pointer_result(result)
        copy = Template.from_string("Pointer(#{result.type_name}).malloc(1, %)", simple: true)
        result.copy_with(
          pointer: 1, reference: false,
          conversion: result.conversion.followed_by(copy),
        )
      end

      class Body < Call::Body
        def initialize(@db : TypeDatabase, @receiver : String, @do_block : Bool, @fallback : String)
        end

        # The body of the `Proc`: the *code* calling the override, converted
        # into the result.  With out arguments, the override returns their
        # values in its tuple, see `Crystal::Pass#wrapper_result`, which is
        # taken apart into the locals the epilogues write back from.
        private def call_body(call, code) : String
          outs = call.arguments.select(Call::OutArgument)
          return call.result.apply_conversion(code) if outs.empty?

          void = call.result.type.pure_void?
          locals = outs.map(&.local)
          locals.unshift("_result_") unless void

          lines = ["#{locals.join(", ")} = #{code}"]
          lines.concat(outs.compact_map(&.epilogue))
          lines << (void ? "nil" : call.result.apply_conversion("_result_"))
          lines.join("\n")
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          typer = Crystal::Typename.new(@db)
          func_result = typer.full(call.result)

          func_args = call.arguments.map { |arg| typer.full(arg) }
          func_args << func_result # Add return type

          # An out-only argument isn't passed to the override.
          passed = call.arguments.reject { |arg| arg.is_a?(Call::OutArgument) && !arg.in_out? }
          pass_args = passed.map(&.call).join(", ")
          proc_args = func_args.join(", ")
          block_arg_names = call.arguments.map(&.name).join(", ")
          block_args = "|#{block_arg_names}|" unless block_arg_names.empty?

          body = call_body(call, "#{@receiver}.#{call.name}(#{pass_args})")
          if @do_block
            %[Proc(#{proc_args}).new do #{block_args} BindgenHelper.rescued(#{@fallback}) do #{body} end end]
          else
            %[Proc(#{proc_args}).new{#{block_args} BindgenHelper.rescued(#{@fallback}) { #{body} } }]
          end
        end
      end
    end
  end
end
