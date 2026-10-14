module Bindgen
  module CallBuilder
    # Builds a `Call` implementing an `#initialize(unwrap : Binding::T*)`.
    class CrystalUnwrapInitialize
      def initialize(@db : TypeDatabase)
      end

      # If *dereference* is set, the argument is a pointer to the value to
      # store, which is copied.
      def build(method : Parser::Method, dereference = false)
        pass = Crystal::Pass.new(@db)
        arg = method.arguments.first

        call_arg = pass.from_binding(arg, qualified: true).to_argument(arg.name)

        target = Call.new(
          origin: method,
          name: arg.name,
          arguments: [] of Call::Argument,
          result: pass.from_binding(arg, qualified: true),
          body: Body.new(dereference),
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
        def initialize(@dereference = false)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          @dereference ? "#{call.name}.value" : call.name
        end
      end
    end
  end
end
