module Bindgen
  module CallBuilder
    # Builder for a `#to_unsafe` wrapper method.
    class CrystalToUnsafe
      METHOD_NAME = "to_unsafe"

      def initialize(@db : TypeDatabase)
      end

      def build(klass : Parser::Class, use_pointerof) : Call
        pass = Crystal::Pass.new(@db)
        method = create_method(klass)
        result = pass.from_binding(method.return_type, qualified: true)

        Call.new(
          origin: method,
          name: METHOD_NAME,
          result: result,
          arguments: [] of Call::Argument,
          body: Body.new(use_pointerof),
        )
      end

      private def create_method(klass)
        Parser::Method.build(
          name: METHOD_NAME,
          class_name: klass.name,
          return_type: klass.as_type,
          arguments: [] of Parser::Argument,
        )
      end

      class Body < Call::Body
        def initialize(@use_pointerof : Bool)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          if @use_pointerof
            var = "pointerof(@unwrap)"
          else
            var = "@unwrap"
          end

          %[def #{call.name}\n] \
          %[  #{var}\n] \
          %[end]
        end
      end
    end
  end
end
