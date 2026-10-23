module Bindgen
  module Cpp
    # Formatter for C++ style code.
    struct Format
      # Formats *arg* as `type name`
      def argument(arg : Call::Argument, idx) : String
        typer = Typename.new
        "#{typer.full arg} #{Argument.name(arg, idx)}"
      end

      # Formats *arguments* as `type name, ...`
      def argument_list(arguments : Enumerable(Call::Argument)) : String
        arguments.map_with_index { |arg, idx| argument(arg, idx) }.join(", ")
      end

      # The statements running *code*, the expression of a call, and returning
      # its result of *result_type*, `nil` for `void`.  Around a call with
      # `Call::OutArgument`s among *arguments*, their prologues declare the
      # locals the call writes to, and their epilogues hand the values back
      # from the result stored in `_result_` meanwhile.
      def out_statements(arguments : Enumerable(Call::Argument), code : String, result_type : String?) : Array(String)
        outs = arguments.select(Call::OutArgument)
        return [result_type ? "return #{code};" : "#{code};"] if outs.empty?

        lines = outs.compact_map(&.prologue)
        lines << (result_type ? "#{result_type} _result_ = #{code};" : "#{code};")
        lines.concat(outs.compact_map(&.epilogue))
        lines << "return _result_;" if result_type
        lines
      end

      # Returns a C++ function pointer type, matching *method*.
      def function_pointer(call : Call) : String
        method = call.origin
        prefix = "#{method.class_name}::" if method.needs_instance?

        typer = Typename.new
        result = typer.full(call.result)
        arguments = call.arguments.map { |arg| typer.full arg }.join(", ")
        "#{result}(#{prefix}*)(#{arguments})"
      end
    end
  end
end
