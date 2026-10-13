module Bindgen
  module CallBuilder
    # Builder for the `.of` macro of container modules.
    class CrystalContainerOf
      def initialize(@db : TypeDatabase)
      end

      def build(method : Parser::Method, container : Configuration::Container) : Call
        raise "not a macro" unless method.macro?

        result = Call::Result.new(
          type: Parser::Type::EMPTY,
          type_name: "",
          reference: false,
          pointer: 0,
        )

        Call.new(
          origin: method,
          name: method.name,
          arguments: [] of Call::Argument,
          result: result,
          body: Body.new(@db, container),
        )
      end

      class Body < Call::Body
        def initialize(@db : TypeDatabase, @container : Configuration::Container)
        end

        def to_code(call : Call, _platform : Graph::Platform) : String
          %[macro #{call.name}(*type_args)\n] \
          %[#{macro_body}\n] \
          %[end]
        end

        private def macro_body
          instantiations = @container.instantiations.map do |inst|
            inst.map { |t| @db.resolve_aliases(t).full_name }
          end.uniq

          if instantiations.empty?
            return %[  {% raise "\#{self} has no instantiations" %}]
          end

          pass = Crystal::Pass.new(@db)
          typer = Crystal::Typename.new(@db)
          cpp_typer = Cpp::Typename.new

          branches = instantiations.map_with_index do |inst, i|
            type_name = cpp_typer.template_class(@container.class, inst)
            templ_type = Parser::Type.parse(type_name)
            templ_args = templ_type.template.not_nil!.arguments

            klass_name = "Container_#{templ_type.mangled_name}"
            arg_list = templ_args.join(", ") do |t|
              @db.try_or(t, typer.full(pass.to_wrapper(t), expects_type: false), &.container_type)
            end

            %[  {% #{i == 0 ? "if" : "elsif"} types == {#{arg_list}} %} {{ #{klass_name} }}\n]
          end

          module_name = Graph::Path.from(@container.class).last_part.camelcase

          %[  {% types = type_args.map(&.resolve) %}\n] \
          %[#{branches.join}] \
          %[  {% else %} {% raise "#{module_name}(\#{types.splat}) has not been instantiated" %}\n] \
          %[  {% end %}]
        end
      end
    end
  end
end
