module Bindgen
  module CallBuilder
    # Builds a `Call` implementing an `#initialize(unwrap : Binding::T*)`.
    class CrystalUnwrapInitialize
      def initialize(@db : TypeDatabase)
      end

      def build(method : Parser::Method)
        pass = Crystal::Pass.new(@db)
        arg = method.arguments.first

        call_arg = pass.from_binding(arg, qualified: true).to_argument(arg.name)

        target = Call.new(
          origin: method,
          name: arg.name,
          arguments: [] of Call::Argument,
          result: pass.from_binding(arg, qualified: true),
          body: Body.new,
        )

        Call.new(
          origin: method,
          name: method.crystal_name,
          arguments: [call_arg],
          result: pass.from_wrapper(Parser::Type::VOID),
          body: CrystalWrapper::ConstructorBody.new(@db, target),
        )
      end

      class Body < Call::Body
        def to_code(call : Call, platform : Graph::Platform) : String
          call.name
        end
      end
    end
  end
end
