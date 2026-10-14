module Bindgen
  module CallBuilder
    # Builds a `Call` implementing a common C/C++ wrapper function.
    class CppWrapper
      include TypeHelper

      def initialize(@db : TypeDatabase)
      end

      def build(method : Parser::Method, target : Call, class_name : String? = nil, self_var = "_self_", needs_instance = nil)
        pass = Cpp::Pass.new(@db)
        class_name ||= cpp_class_name(method.class_name)

        if needs_instance.nil?
          needs_instance = method.needs_instance?
        end

        arguments = pass.arguments_to_cpp(method.arguments)
        if needs_instance # Add `_self_`
          klass_type = Parser::Type.parse(class_name, 1)
          arguments.unshift(Cpp::Argument.self(klass_type))
        end

        Call.new(
          origin: method,
          name: method.mangled_name,
          arguments: arguments,
          result: pass.to_crystal(method.return_type, is_constructor: method.any_constructor?),
          body: Body.new(target),
        )
      end

      class Body < Call::Body
        def initialize(@target : Call)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          formatter = Cpp::Format.new
          typer = Cpp::Typename.new
          func_result = typer.full(call.result)
          func_args = formatter.argument_list(call.arguments)

          # Returning a `void` from a void method generates a warning.
          prefix = "return " unless call.result.type.pure_void?

          %[extern "C" #{func_result} #{call.name}(#{func_args}) {\n] \
          %[  #{prefix}#{@target.body.to_code(@target, platform)};\n] \
          %[}\n\n]
        end
      end
    end
  end
end
