module Bindgen
  module CallBuilder
    # Builds an `abstract def`.
    class CrystalAbstractDef
      def initialize(@db : TypeDatabase)
      end

      def build(method : Parser::Method)
        pass = Crystal::Pass.new(@db)
        arguments = pass.arguments_to_wrapper(method.arguments, method.out_arguments(@db))

        Call.new(
          origin: method,
          name: method.crystal_name,
          arguments: arguments,
          result: pass.wrapper_result(method),
          body: Body.new(@db),
        )
      end

      class Body < Call::Body
        def initialize(@db : TypeDatabase)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          method = Crystal::Method.new(@db)
          method.prototype(
            name: call.name,
            arguments: call.arguments,
            result: call.result,
            static: call.origin.static?,
            abstract: true,
            protected: call.origin.protected?,
          )
        end
      end
    end
  end
end
