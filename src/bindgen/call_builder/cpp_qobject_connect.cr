module Bindgen
  module CallBuilder
    # Builds a `QObject::connect` sequence.
    class CppQobjectConnect
      def initialize(@db : TypeDatabase)
      end

      def build(method : Parser::Method, proc)
        pass = Cpp::Pass.new(@db)

        Call.new(
          origin: method,
          name: "#{method.class_name}::#{method.name}",
          arguments: pass.arguments_from_cpp(method.arguments),
          result: pass.to_crystal(Processor::Qt::CONNECTION_HANDLE_TYPE),
          body: Body.new(proc),
        )
      end

      class Body < Call::Body
        def initialize(@lambda : Call)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          formatter = Cpp::Format.new

          lambda_body = @lambda.body.to_code(@lambda, platform)
          ptr = formatter.function_pointer(@lambda)

          code = %[QObject::connect(_self_, (#{ptr})&#{call.name}, #{lambda_body})]

          call.result.apply_conversion(code)
        end
      end
    end
  end
end
