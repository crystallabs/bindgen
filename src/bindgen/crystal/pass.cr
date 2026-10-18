module Bindgen
  module Crystal
    # Methods for passing data from Crystal and Crystal bindings to C++.
    #
    # This is a helper struct: Cheap to create and to pass around.
    struct Pass
      Log = ::Log.for(self)

      include TypeHelper

      def initialize(@db : TypeDatabase)
      end

      # Turns the list of arguments into a list of `Call::Argument`s.
      def arguments_to_binding(list : Enumerable(Parser::Argument))
        argument = Argument.new(@db)

        list.map_with_index do |arg, idx|
          if idx == list.size - 1 && arg.variadic?
            variadic_argument
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
            next variadic_argument
          end

          result = to_wrapper(arg)
          name = argument.name(arg, idx)

          Log.trace { "arg to wrapper name: #{name}" }
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
        Log.trace &.emit "convert to binding", type: type.full_name, to_unsafe: to_unsafe, qualified: qualified

        return array_pointer_to_binding(type, qualified) if type.pointer_to_c_array?

        to(type) do |is_ref, ptr, nilable|
          typer = Typename.new(@db)
          type_name, in_lib = typer.binding(type)

          Log.trace &.emit("binding type_name",
            type: type.full_name,
            type_name: type_name,
            in_lib: in_lib,
            builtin: type.builtin?
          )

          if qualified
            type_name = typer.qualified(type_name, in_lib) if qualified
            Log.trace &.emit("qualified type_name",
              type: type.full_name,
              type_name: type_name
            )
          end

          template = Template::None.new

          if rules = @db[type]?
            template = type_template(rules.converter, rules.from_crystal, "wrap")
            is_ref, ptr = reconfigure_pass_type(rules.pass_by, is_ref, ptr)

            if template.no_op? && !rules.builtin? && !type.builtin?
              if !is_ref && ptr == 0 && structure_hosted?(rules)
                # The wrapper class hosts the structure, its `#to_unsafe`
                # returns a pointer to it.  Pass a copy by value.
                template = Template.from_string("%.to_unsafe.value", simple: true)
              elsif to_unsafe && (rules.generate_wrapper? || !rules.copy_structure?)
                # Not for a copied structure without a wrapper, as it's the
                # `lib struct` itself.
                template = Template.from_string("%.to_unsafe", simple: true)
              elsif nilable && rules.kind.class? && !rules.copy_structure? && ptr == 1 && !is_ref
                # A nilable wrapper is converted explicitly: Crystal passes
                # `nil` or an object to a pointer parameter, but not their
                # union, which a nilable variable is.
                null = "Pointer(#{typer.qualified(type_name, in_lib)}).null"
                template = Template.from_string("(%.try(&.to_unsafe) || #{null})", simple: true)
              end
            end
          end

          if type.kind.function?
            type_name = Parser::Type::CRYSTAL_PROC
            template = Template::ProcFromWrapper.new(type, @db).followed_by(
              Template.from_string("BindgenHelper.wrap_proc(%)", simple: true).followed_by(template))
            ptr = 0
            is_ref = false
          end

          ptr += 1 if is_ref # Translate reference to pointer
          is_ref = false

          Log.trace &.emit("determined type_name",
            type: type.full_name,
            type_name: type_name
          )

          {is_ref, ptr, type_name, template, false}
        end
      end

      # Builds the type-name of a Crystal `Proc` for Crystal wrappers, from the
      # function *type*.
      private def proc_to_wrapper(type)
        args = type.template_arguments

        # The order used to store is result type first, arguments second,
        # mirroring C function prototypes.  Crystal Procs are formatted in the
        # opposite direction, so we have to reverse it.
        types = args[1..-1]
        types << args.first
        names = types.map { |t| to_wrapper(t).type_name.as(String) }.join(", ")

        "Proc(#{names})"
      end

      # Passes the pointer or reference to a C array *type* as pointer to a
      # `StaticArray`.  A reference is made from a `Slice` in the wrapper, see
      # `#to_wrapper`, or from a `BindgenHelper::ArrayView` passed as pointer to
      # its first element.
      private def array_pointer_to_binding(type, qualified) : Call::Result
        typer = Typename.new(@db)
        type_name, in_lib = typer.binding(type)
        type_name = typer.qualified(type_name, in_lib) if qualified
        template = Template::None.new

        if type.reference_to_c_array? && @db.array_view?(type.pointee_array)
          # The view's pointer to the first element.
          template = Template.from_string("BindgenHelper.view_to_array(%, #{type.extents.first})", simple: true)
          return Call::Result.new(
            type: type.pointee_array.remove_all_extents,
            type_name: type_name,
            reference: false,
            pointer: 1,
            conversion: template,
          )
        elsif type.reference_to_c_array?
          # The conversion is done in the wrapper, outside of the `lib`.
          element = typer.qualified(*typer.binding(type))
          array = typer.full(array_pointer_result(type.pointee_array, element), expects_type: false)
          template = Template.from_string("BindgenHelper.slice_to_array(%, #{array})", simple: true)
        end

        array_pointer_result(type, type_name, template)
      end

      # Builds the result of a C array *type*, or a pointer or reference to
      # one, whose element type is named *type_name*.
      private def array_pointer_result(type, type_name, template = Template::None.new, nilable = false)
        Call::Result.new(
          type: type,
          type_name: type_name,
          reference: false,
          pointer: type.pointer - type.extents.size,
          conversion: template,
          nilable: nilable,
        )
      end

      # Computes a result for passing *type* to the wrapper.
      def to_wrapper(type : Parser::Type) : Call::Result
        if type.reference_to_c_array?
          # Taken as `Slice` of the elements of the referenced array, or as
          # `BindgenHelper::ArrayView` of wrapped classes.
          typer = Typename.new(@db)
          array = type.pointee_array
          element = array_pointer_result(array.array_element, typer.qualified(*typer.wrapper(type)))
          container = @db.array_view?(array) ? "BindgenHelper::ArrayView" : "Slice"

          return Call::Result.new(
            type: array.remove_all_extents,
            type_name: "#{container}(#{typer.full(element, expects_type: false)})",
            reference: false,
            pointer: 0,
          )
        end

        if type.pointer_to_c_array?
          typer = Typename.new(@db)
          return array_pointer_result(type, typer.qualified(*typer.wrapper(type)), nilable: type.nilable?)
        end

        to(type) do |is_ref, ptr, nilable|
          typename = Typename.new(@db)
          type_name = typename.qualified(*typename.wrapper(type))
          type_name = proc_to_wrapper(type) if type.kind.function?

          if rules = @db[type]?
            if rules.kind.class? || rules.kind.function?
              ptr -= 1 # It's a Crystal `Reference`.
            end

            is_ref, ptr = reconfigure_pass_type(rules.crystal_pass_by, is_ref, ptr)
          end

          if type.kind.function?
            is_ref = false
            ptr = 0
          end

          ptr += 1 if is_ref # Translate reference to pointer
          is_ref = false
          {is_ref, ptr, type_name, Template::None.new, nilable}
        end
      end

      def to(type : Parser::Type, &) : Call::Result
        is_copied = type_copied?(type)
        is_ref = type.reference?
        is_val = type.pointer < 1
        ptr = type_pointer_depth(type)
        nilable = type.nilable?

        # If the method expects a value, but we don't copy its structure, we pass
        # a reference to it instead.
        if is_val && !is_copied
          is_ref = true
          ptr = 0
        end

        # Hand-off
        is_ref, ptr, type_name, template, nilable = yield is_ref, ptr, nilable

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
        Log.trace &.emit "from binding", type: type.base_name, qualified: qualified, is_constructor: is_constructor

        # The referenced array becomes a `Slice` like an array member.
        type = type.pointee_array if type.reference_to_c_array?
        return array_pointer_to_binding(type, qualified) if type.pointer_to_c_array?

        from(type, is_constructor: is_constructor, no_slice: no_slice) do |is_ref, ptr, _nilable|
          typer = Typename.new(@db)

          if qualified
            type_name = typer.qualified(*typer.binding(type))
          else
            type_name, _ = typer.binding(type)
          end

          Log.trace { "type_name: #{type_name}" }
          template = Template::None.new

          if type.c_array? && !no_slice && @db.array_view?(type)
            is_ref = false
            ptr = 0
            element = typer.qualified(*typer.wrapper(type.array_element))
            template = Template::Basic.new("BindgenHelper::ArrayView(#{element}).new(%)", simple: true)
            type_name = "Binding::CrystalArray"
          elsif type.c_array? && !no_slice
            is_ref = false
            ptr = 0
            inner_result = from_binding(type.array_element, qualified: true, no_slice: true)
            template = Template::Basic.new("BindgenHelper::SliceConverter(#{typer.full(inner_result)}).unwrap(%)", simple: true)
            type_name = "Binding::CrystalSlice"
          end

          if rules = @db[type]?
            unless is_constructor
              template = type_template(rules.converter, rules.to_crystal, "unwrap") if template.no_op?
            end

            is_ref, ptr = reconfigure_pass_type(rules.pass_by, is_ref, ptr)
          end

          {is_ref, ptr, type_name, template, false}
        end
      end

      # Computes a result for passing *type* from the wrapper to the user.
      def from_wrapper(type : Parser::Type, is_constructor = false, no_slice = false, callback_argument = false) : Call::Result
        Log.trace &.emit "from wrapper", type: type.base_name, is_constructor: is_constructor

        type = type.pointee_array if type.reference_to_c_array?

        if type.pointer_to_c_array?
          typer = Typename.new(@db)
          return array_pointer_result(type, typer.qualified(*typer.wrapper(type)))
        end

        from(type, no_slice: no_slice) do |is_ref, ptr, nilable|
          typer = Typename.new(@db)
          local_type_name, in_lib = typer.wrapper(type)
          type_name = typer.qualified(local_type_name, in_lib)

          template = Template::None.new

          if rules = @db[type]?
            if rules.kind.class?
              ptr -= 1
            end

            # Do not return types like `Bool*?` from the wrapper.
            if rules.builtin? && ptr > 0 && !is_ref
              nilable = false
            end

            array = type.c_array? && !no_slice
            if array && @db.array_view?(type)
              is_ref = false
              ptr = 0
              type_name = "BindgenHelper::ArrayView(#{typer.qualified(*typer.wrapper(type.array_element))})"
            elsif array
              is_ref = false
              ptr = 0
              inner_result = from_wrapper(type.array_element, no_slice: true)
              type_name = "Slice(#{typer.full(inner_result)})"
            end

            if !array && !rules.builtin? && !is_constructor && !rules.converter && rules.to_crystal.no_op? && !in_lib && !rules.kind.enum?
              # A pointer to a wrapped class may be null, see `nilable_results`.
              # Not for the argument of a callback, which a Crystal override
              # takes as declared, nor for a type known to be non-null.
              nilable ||= @db.nilable_results? && !callback_argument && !type.never_nil? &&
                          rules.kind.class? && type.pointer == 1 && !type.reference?
              template = wrapper_initialize_template(rules, type_name, nilable)
            end

            is_ref, ptr = reconfigure_pass_type(rules.crystal_pass_by, is_ref, ptr)
          end

          ptr += 1 if is_ref # Translate reference to pointer
          is_ref = false

          {is_ref, ptr, type_name, template, nilable}
        end
      end

      def from(type : Parser::Type, is_constructor = false, no_slice = false, &) : Call::Result
        is_copied = type_copied?(type)
        is_ref = type.reference?
        is_val = type.pointer < 1
        ptr = type_pointer_depth(type)
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
        is_ref, ptr, type_name, template, nilable = yield is_ref, ptr, nilable
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
