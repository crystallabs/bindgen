module Bindgen
  module CallBuilder
    # Builder for a `#superclass` wrapper method.
    class CrystalSuperclass
      METHOD_NAME = "superclass"

      def initialize(@db : TypeDatabase)
      end

      def build(superklass : Parser::Class) : Call
        method = create_method(superklass)
        result = Call::Result.new(
          type: superklass.as_type,
          type_name: superklass.name,
          reference: false,
          pointer: 0,
        )

        Call.new(
          origin: method,
          name: METHOD_NAME,
          result: result,
          arguments: [] of Call::Argument,
          body: Body.new,
        )
      end

      private def create_method(superklass)
        Parser::Method.build(
          name: METHOD_NAME,
          access: Parser::AccessSpecifier::Protected,
          class_name: superklass.name,
          return_type: superklass.as_type,
          arguments: [] of Parser::Argument,
        )
      end

      class Body < Call::Body
        def to_code(call : Call, _platform : Graph::Platform) : String
          %[private def #{call.name}\n] \
          %[  #{call.result.type.base_name}.new(self)\n] \
          %[end]
        end
      end
    end
  end
end
