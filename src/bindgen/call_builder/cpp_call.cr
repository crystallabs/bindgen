module Bindgen
  module CallBuilder
    # Builds a `Call` calling a C/C++ function.
    class CppCall
      def initialize(@db : TypeDatabase)
      end

      def build(method : Parser::Method, self_var = "_self_", body : Call::Body? = nil, name : String? = nil)
        pass = Cpp::Pass.new(@db)

        method_name = Cpp::MethodName.new(@db)
        name ||= method_name.generate(method, self_var)

        Call.new(
          origin: method,
          name: name,
          arguments: pass.arguments_to_cpp(method.arguments),
          result: pass.to_crystal(method.return_type),
          body: (body || Body.new),
        )
      end

      # Body used by `CppCall` and `CppMethodCall`.
      class Body < Call::Body
        def to_code(call : Call, _platform : Graph::Platform) : String
          pass_args = call.arguments.map(&.call).join(", ")
          code = %[#{call.name}(#{pass_args})]
          call.result.apply_conversion(code)
        end
      end
    end
  end
end
