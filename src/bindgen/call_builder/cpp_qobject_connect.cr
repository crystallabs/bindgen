module Bindgen
  module CallBuilder
    # Builds a `QObject::connect` sequence.
    #
    # The connection gets a context object and a connection type, which the
    # context-less functor overload of `QObject::connect` lacks: that one
    # always calls the functor on the emitting thread, as a direct connection.
    # The context is the application object, so an `Qt::AutoConnection` from a
    # Qt thread is queued to the main thread, the only thread allowed to run
    # Crystal code.  Before there is an application, the sender is the context.
    # The connection type is an argument of the connection method.
    class CppQobjectConnect
      # The context object of the connection: The application, else the sender.
      CONTEXT = "QCoreApplication::instance() ? static_cast<QObject *>(QCoreApplication::instance()) : static_cast<QObject *>(_self_)"

      def initialize(@db : TypeDatabase)
      end

      # Builds the connection of the signal *method* to the lambda *proc*.
      # *connection_type* names the C++ argument holding the
      # `Qt::ConnectionType`.
      def build(method : Parser::Method, proc, connection_type : String)
        pass = Cpp::Pass.new(@db)

        Call.new(
          origin: method,
          name: "#{method.class_name}::#{method.name}",
          arguments: pass.arguments_from_cpp(method.arguments),
          result: pass.to_crystal(Processor::Qt::CONNECTION_HANDLE_TYPE),
          body: Body.new(proc, connection_type),
        )
      end

      class Body < Call::Body
        def initialize(@lambda : Call, @connection_type : String)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          formatter = Cpp::Format.new

          lambda_body = @lambda.body.to_code(@lambda, platform)
          ptr = formatter.function_pointer(@lambda)

          code = %[QObject::connect(_self_, (#{ptr})&#{call.name}, #{CONTEXT}, #{lambda_body}, #{@connection_type})]

          call.result.apply_conversion(code)
        end
      end
    end
  end
end
