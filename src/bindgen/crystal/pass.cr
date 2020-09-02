module Bindgen
  module Crystal
    # Methods for passing data from Crystal and Crystal bindings to C++.
    #
    # This is a helper struct: Cheap to create and to pass around.
    struct Pass
      include TypeHelper

      def initialize(@db : TypeDatabase)
      end

      # Turns the list of arguments into a list of `Call::Argument`s.
      def arguments_to_binding(list : Enumerable(Parser::Argument))
        argument = Argument.new(@db)

        list.map_with_index do |arg, idx|
          if idx == list.size - 1 && arg.variadic?
            self.variadic_argument
          else
            to_binding(arg).to_argument(argument.name(arg, idx))
          end
        end
      end

      # Turns the list of arguments into a list of `Call::Argument`s.
      def arguments_to_wrapper(list : Enumerable(Parser::Argument))
        argument = Argument.new(@db)

        list.map_with_index do |arg, idx|
          is_last = (idx == list.size - 1)
          if is_last && arg.variadic? # Support variadic argument
            next self.variadic_argument
          end

          result = to_wrapper(arg)
          name = argument.name(arg, idx)

          if result.is_a?(Call::ProcResult)
            # Treat as block if it's the last argument.
            result.to_argument(name, block: is_last)
          else
            value = arg.value if arg.has_default?
            result.to_argument(name, default: value)
          end
        end
      end

      # Computes a result for passing *type* from Crystal to C++.  If
      # *to_unsafe* is `true`, and the type is not built-in, the result will
      # be wrapped in a call to `to_unsafe` - Except if a user-defined
      # conversion is set.
      def to_binding(type : Parser::Type, to_unsafe = false, qualified = false) : Call::Result
        to(type) do |is_ref, ptr, type_name, nilable|
          typer = Typename.new(@db)
          type_name, in_lib = typer.binding(type)
          type_name = typer.qualified(type_name, in_lib) if qualified

          template = Template::None.new

          if rules = @db[type]?
            template = type_template(rules.converter, rules.from_crystal, "wrap")
            template = Template.from_string("%.to_unsafe", simple: true) if
              template.no_op? && to_unsafe && !rules.builtin && !type.builtin?

            is_ref, ptr = reconfigure_pass_type(rules.pass_by, is_ref, ptr)
          end

          if type.kind.function?
            template = Template::ProcFromWrapper.new(type, @db).followed_by(template)
          end

          ptr += 1 if is_ref # Translate reference to pointer
          is_ref = false
          {is_ref, ptr, type_name, template, false}
        end
      end

      # Builds the type-name of a Crystal `Proc` for Crystal wrappers, from the
      # function *type*.
      private def proc_to_wrapper(type)
        args = type.template.not_nil!.arguments

        # The order used to store is result type first, arguments second,
        # mirroring C function prototypes.  Crystal Procs are formatted in the
        # opposite direction, so we have to reverse it.
        types = args[1..-1]
        types << args.first
        names = types.map { |t| to_wrapper(t).type_name.as(String) }.join(", ")

        "Proc(#{names})"
      end

      # Computes a result for passing *type* to the wrapper.
      def to_wrapper(type : Parser::Type) : Call::Result
        to(type) do |is_ref, ptr, type_name, nilable|
          typename = Typename.new(@db)
          type_name = typename.qualified(*typename.wrapper(type))
          type_name = proc_to_wrapper(type) if type.kind.function?

          if rules = @db[type]?
            if rules.kind.class? || rules.kind.function?
              ptr -= 1 # It's a Crystal `Reference`.
            end

            is_ref, ptr = reconfigure_pass_type(rules.crystal_pass_by, is_ref, ptr)
          end

          ptr += 1 if is_ref # Translate reference to pointer
          is_ref = false
          {is_ref, ptr, type_name, Template::None.new, nilable}
        end
      end

      def to(type : Parser::Type) : Call::Result
        is_copied = is_type_copied?(type)
        is_ref = type.reference?
        is_val = type.pointer < 1
        ptr = type_pointer_depth(type)
        type_name = type.base_name
        nilable = type.nilable?

        # If the method expects a value, but we don't copy its structure, we pass
        # a reference to it instead.
        if is_val && !is_copied
          is_ref = true
          ptr = 0
        end

        # Hand-off
        is_ref, ptr, type_name, template, nilable = yield is_ref, ptr, type_name, nilable

        klass = type.kind.function? ? Call::ProcResult : Call::Result
        klass.new(
          type: type,
          type_name: type_name,
          reference: is_ref,
          pointer: {0, ptr}.max,
          conversion: template,
          nilable: nilable,
        )
      end

      # Computes a result for passing *type* from C++ to Crystal.
      #
      # If *qualified* is `true`, the type is assumed to be used outside the
      # `lib Binding`, and will be qualified if required.
      def from_binding(type : Parser::Type, qualified = false, is_constructor = false, no_slice = false) : Call::Result
        from(type, is_constructor, no_slice) do |is_ref, ptr, type_name, nilable|
          typer = Typename.new(@db)

          if qualified
            type_name = typer.qualified(*typer.binding(type))
          else
            type_name, _ = typer.binding(type)
          end

          template = Template::None.new

          if type.c_array? && !no_slice
            is_ref = false
            ptr = 0
            inner_result = from_binding(type.decayed.not_nil!, no_slice: true)
            template = "BindgenHelper::SliceConverter(#{typer.full(inner_result)}).unwrap(%)"
            type_name = "Binding::CrystalSlice"
          end

          if rules = @db[type]?
            unless is_constructor
              template ||= type_template(rules.converter, rules.to_crystal, "unwrap")
            end

            is_ref, ptr = reconfigure_pass_type(rules.pass_by, is_ref, ptr)
          end

          {is_ref, ptr, type_name, template, false}
        end
      end

      # Computes a result for passing *type* from the wrapper to the user.
      def from_wrapper(type : Parser::Type, is_constructor = false, no_slice = false) : Call::Result
        from(type, is_constructor, no_slice) do |is_ref, ptr, type_name, nilable|
          typer = Typename.new(@db)
          local_type_name, in_lib = typer.wrapper(type)
          type_name = typer.qualified(local_type_name, in_lib)

          template = Template::None.new

          if rules = @db[type]?
            if rules.kind.class?
              ptr -= 1
            end

            # Do not return types like `Bool*?` from the wrapper.
            if rules.builtin && ptr > 0 && !is_ref
              nilable = false
            end

            if type.c_array? && !no_slice
              is_ref = false
              ptr = 0
              inner_result = from_wrapper(type.decayed.not_nil!, no_slice: true)
              type_name = "Slice(#{typer.full(inner_result)})"
            end

            if !rules.builtin && !is_constructor && !rules.converter && rules.to_crystal.no_op? && !in_lib && !rules.kind.enum?
              template = wrapper_initialize_template(rules, type_name, nilable)
            end

            is_ref, ptr = reconfigure_pass_type(rules.crystal_pass_by, is_ref, ptr)
          end

          ptr += 1 if is_ref # Translate reference to pointer
          is_ref = false

          {is_ref, ptr, type_name, template, nilable}
        end
      end

      def from(type : Parser::Type, is_constructor = false, no_slice = false) : Call::Result
        is_copied = is_type_copied?(type)
        is_ref = type.reference?
        is_val = type.pointer < 1
        ptr = type_pointer_depth(type)
        type_name = type.base_name
        nilable = type.nilable?

        # TODO: Check for copy-constructor.
        if is_constructor && is_copied
          is_ref = false
          ptr = 0
        elsif is_ref || (is_val && !is_copied)
          is_ref = false
          ptr = 1
        end

        # Hand-off
        is_ref, ptr, type_name, template, nilable = yield is_ref, ptr, type_name, nilable
        ptr += 1 if is_ref # Translate reference to pointer
        ptr -= type.extents.size
        type = type.remove_all_extents unless no_slice

        Call::Result.new(
          type: type,
          type_name: type_name,
          reference: is_ref,
          pointer: {0, ptr}.max,
          conversion: template,
          nilable: nilable,
        )
      end

      # Helper which chooses the *converter* if set, or falls back to the
      # *translator*.
      #
      # *converter* is set by the user as `converter:` field in the type
      # configuration, while *translator* is influenced by `to_crystal:` or
      # `from_crystal:`.
      private def type_template(converter, translator, conv_name) : Template::Base
        if converter
          Template.from_string "#{converter}.#{conv_name}(%)", simple: true
        else
          translator
        end
      end

      # Returns the `Call::Result#conversion` template to turn a pointer into an
      # instance of *type_name* by using its `#initialize(unwrap: x)` method.
      private def wrapper_initialize_template(rules, type_name, nilable)
        # If the target type is abstract, use its `Impl` class instead.
        if klass = rules.graph_node.as?(Graph::Class)
          if impl = klass.wrap_class
            type_name = impl.name
          end
        end

        template_string = if nilable
          %[%.try {|ptr| #{type_name}.new(unwrap: ptr) unless ptr.null?}]
        else
          "#{type_name}.new(unwrap: %)"
        end

        Template.from_string template_string, simple: true
      end
    end
  end
end
