module Bindgen
  module CallBuilder
    # Builder for the `#initialize` method inside a superclass wrapper.
    class CrystalSuperclassInit
      def initialize(@db : TypeDatabase)
      end

      def build(method : Parser::Method, parent_klass : Parser::Class) : Call
        myself = Crystal::Argument.new(@db).myself(parent_klass.as_type)

        result = Call::Result.new(
          type: method.return_type,
          type_name: method.name,
          reference: false,
          pointer: 0,
        )

        Call.new(
          origin: method,
          name: method.crystal_name,
          result: result,
          arguments: [myself],
          body: Body.new(@db),
        )
      end

      class Body < Call::Body
        def initialize(@db : TypeDatabase)
        end

        def to_code(call : Call, _platform : Graph::Platform) : String
          formatter = Crystal::Format.new(@db)

          %[def #{call.name}(#{formatter.argument_list(call.arguments)})\n] \
          %[end]
        end
      end
    end
  end
end
