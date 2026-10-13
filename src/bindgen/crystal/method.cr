module Bindgen
  module Crystal
    # Functionality to generate method code.
    struct Method
      def initialize(@db : TypeDatabase)
      end

      # Builds the prototype ("first line") of a method.
      def prototype(
        name, arguments, result = nil, static = false,
        abstract abstract_ = false, protected protected_ = false,
        private private_ = false, named_args = false,
      ) : String
        formatter = Format.new(@db)
        typer = Typename.new(@db)
        func_result = typer.full(result) if result
        if named_args && !arguments.empty?
          func_args = formatter.named_argument_list(arguments)
        else
          func_args = formatter.argument_list(arguments)
        end

        kind = ""
        suffix = " : #{func_result}" if func_result
        name_prefix = "self." if static
        kind = "protected " if protected_
        kind = "private " if private_
        kind += "abstract " if abstract_

        %[#{kind}def #{name_prefix}#{name}(#{func_args})#{suffix}]
      end
    end
  end
end
