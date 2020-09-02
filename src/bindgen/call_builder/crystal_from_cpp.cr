module Bindgen
  module CallBuilder
    # Builder for calls made from C++ to a Crystal `CrystalProc`.
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

        arguments = method.arguments.map_with_index do |arg, idx|
          caller = pass.from_binding(arg, qualified: true)
          callee = pass.from_wrapper(arg)
          result = combine_result(caller, callee)
          result.to_argument(argument.name(arg, idx))
        end

        callee = pass.to_wrapper(method.return_type)
        caller = pass.to_binding(method.return_type, to_unsafe: true, qualified: true)
        result = combine_result(caller, callee)

        Call.new(
          origin: method,
          name: method.crystal_name,
          result: result,
          arguments: arguments,
          body: Body.new(@db, receiver, do_block),
        )
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

      class Body < Call::Body
        def initialize(@db : TypeDatabase, @receiver : String, @do_block : Bool)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          formatter = Crystal::Format.new(@db)
          typer = Crystal::Typename.new(@db)
          func_result = typer.full(call.result)

          func_args = call.arguments.map { |arg| typer.full(arg) }
          func_args << func_result # Add return type

          pass_args = call.arguments.map(&.call).join(", ")
          proc_args = func_args.join(", ")
          block_arg_names = call.arguments.map(&.name).join(", ")
          block_args = "|#{block_arg_names}|" unless pass_args.empty?

          body = call.result.apply_conversion "#{@receiver}.#{call.name}(#{pass_args})"
          if @do_block
            %[Proc(#{proc_args}).new do #{block_args} #{body} end]
          else
            %[Proc(#{proc_args}).new{#{block_args} #{body} }]
          end
        end
      end
    end
  end
end
