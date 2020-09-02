module Bindgen
  module Template
    # Custom template to transform `Proc`s for Crystal wrapper types into `Proc`
    # expressions for binding types.
    class ProcFromWrapper < Base
      def initialize(@proc_type : Parser::Type, @db : TypeDatabase)
      end

      def no_op? : Bool
        false
      end

      def template(code) : String
        args = @proc_type.template.not_nil!.arguments
        func_args = args[1..-1].map_with_index do |type, i|
          Parser::Argument.new("arg#{i}", type)
        end
        proc_call = Parser::Method.build(
          name: "call",
          return_type: args.first,
          arguments: func_args,
          class_name: "Proc",
        )

        builder = CallBuilder::CrystalFromCpp.new(@db)
        call = builder.build(proc_call, receiver: "_proc_", do_block: true)
        call.body.to_code(call, Graph::Platform::Crystal)
      end

      def_equals @proc_type, @db
    end
  end
end
