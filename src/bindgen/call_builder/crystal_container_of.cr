module Bindgen
  module CallBuilder
    # Builder for the `.of` macro of container modules.
    class CrystalContainerOf
      def initialize(@db : TypeDatabase)
      end

      def build(method : Parser::Method, containers : Array(Configuration::Container)) : Call
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
          body: Body.new(@db, containers),
        )
      end

      class Body < Call::Body
        def initialize(@db : TypeDatabase, @containers : Array(Configuration::Container))
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          %[macro #{call.name}(*type_args)\n] \
          %[#{macro_body}\n] \
          %[end]
        end

        private def macro_body
          pass = Crystal::Pass.new(@db)
          typer = Crystal::Typename.new(@db)
          cpp_typer = Cpp::Typename.new

          # Maps the Crystal type arguments to the wrapper class.  If several
          # containers offer the same instantiation, the first one wins.  Type
          # aliases were resolved by `Processor::InstantiateContainers`.
          wrappers = {} of String => String

          @containers.each do |container|
            container.instantiations.each do |inst|
              type_name = cpp_typer.template_class(container.class, inst)
              templ_type = Parser::Type.parse(type_name)
              templ_args = templ_type.template_arguments

              arg_list = templ_args.join(", ") do |t|
                @db.try_or(t, typer.full(pass.to_wrapper(t), expects_type: false), &.container_type)
              end

              wrappers[arg_list] ||= "Container_#{templ_type.mangled_name}"
            end
          end

          if wrappers.empty?
            return %[  {% raise "\#{self} has no instantiations" %}]
          end

          branches = wrappers.map_with_index do |(arg_list, klass_name), i|
            %[  {% #{i == 0 ? "if" : "elsif"} types == {#{arg_list}} %} {{ #{klass_name} }}\n]
          end

          module_name = Graph::Path.from(@containers.first.class).last_part.camelcase

          %[  {% types = type_args.map(&.resolve) %}\n] \
          %[#{branches.join}] \
          %[  {% else %} {% raise "#{module_name}(\#{types.splat}) has not been instantiated" %}\n] \
          %[  {% end %}]
        end
      end
    end
  end
end
