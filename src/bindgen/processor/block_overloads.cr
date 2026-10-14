module Bindgen
  module Processor
    # Generates overloads for methods that accept a single block argument.
    # Those methods are ambiguous because Crystal does not permit overloading
    # through different type restrictions on the block; this processor rectifies
    # this by requiring each overload to also specify the types of the block
    # parameters.  For example, the following code
    #
    # ```
    # def f(& : Int32 ->)
    # end
    #
    # def f(& : Bool ->)
    # end
    #
    # def f(& : Int32, Bool ->)
    # end
    # ```
    #
    # is transformed into
    #
    # ```
    # def f(_type1_ : Int32.class, & : Int32 ->)
    # end
    #
    # def f(_type1_ : Bool.class, & : Bool ->)
    # end
    #
    # def f(_type1_ : Int32.class, _type2_ : Bool.class, & : Int32, Bool ->)
    # end
    # ```
    #
    # Unambiguous methods that accept block arguments are unaffected.
    class BlockOverloads < Base
      PLATFORM = Graph::Platform::Crystal

      def visit_platform_specific(specific)
        super if specific.platforms.includes?(PLATFORM)
      end

      def visit_class(klass)
        methods_by_name = klass.nodes.compact_map do |node|
          if method = node.as?(Graph::Method)
            if call = method.calls[PLATFORM]?
              # only select methods with a single block argument
              if call.arguments.size == 1 && call.arguments.last.is_a?(Call::ProcArgument)
                {method, call}
              end
            end
          end
        end.group_by { |_, call| call.name }

        typer = Crystal::Typename.new(@db)

        methods_by_name.each do |_name, overloads|
          next if overloads.size == 1
          overloads.each do |_method, call|
            proc_type = call.arguments.last.as(Call::ProcArgument).type
            proc_args = proc_type.template_arguments.skip(1) # ignore return type
            arg_count = proc_args.size

            proc_args.reverse_each.with_index do |proc_arg, i|
              # generate unique parameter name in order
              name = "_type#{arg_count - i}_"
              type_name, _ = typer.wrapper(proc_arg)

              call.arguments.unshift(Call::TypeArgument.new(
                type: proc_arg.as(Parser::Type),
                type_name: type_name,
                name: name,
                call: name,
              ))
            end
          end
        end

        super
      end
    end
  end
end
