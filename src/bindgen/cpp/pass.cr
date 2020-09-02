module Bindgen
  module Cpp
    # Methods for passing data from and to C++.
    #
    # This is a helper struct: Cheap to create and to pass around.
    struct Pass
      include TypeHelper

      def initialize(@db : TypeDatabase)
      end

      # Turns the list of arguments into a list of `Call::Argument`s.
      def arguments_to_cpp(list : Enumerable(Parser::Argument))
        list.map_with_index do |arg, idx|
          to_cpp(arg).to_argument(Argument.name(arg, idx))
        end
      end

      # ditto
      def arguments_from_cpp(list : Enumerable(Parser::Argument))
        list.map_with_index do |arg, idx|
          passthrough_to_crystal(arg).to_argument(Argument.name(arg, idx))
        end
      end

      # ditto
      def through_arguments(list : Enumerable(Parser::Argument))
        list.map_with_index do |arg, idx|
          through(arg).to_argument(Argument.name(arg, idx))
        end
      end

      # Returns the type name of *type*, ignoring conversion templates.
      def type_name_base(type : Parser::Type) : String
        if type.c_array?
          # Note: `CrystalSlice` was supposed to be a template type, but
          # `extern "C"` functions cannot return template types, so the element
          # type is always erased.
          "CrystalSlice"
        elsif type.kind.function?
          crystal_proc_name(type)
        else
          type.base_name
        end
      end

      # Returns the type name of *proc_type*.
      private def crystal_proc_name(proc_type : Parser::Type) : String
        typer = Typename.new
        inner_args = proc_type.template.not_nil!.arguments

        # Arguments go C++ -> Crystal, but the result goes Crystal -> C++!
        proc_types = inner_args[1..-1].map { |t| to_crystal(t).as(Call::Result) }
        proc_types.unshift to_cpp(inner_args.first)

        proc_args = typer.full(proc_types).join(", ")
        "CrystalProc<#{proc_args}>"
      end

      # Computes a result for passing *type* from Crystal to C++.
      #
      # The primary job of this method is to figure out how to pass something of
      # *type* over to C++.  It doesn't matter if this is a result from a method
      # or an argument for this.  It also signals how a value of this type shall
      # be handled by the receiver, e.g., if conversions apply (Which?).
      #
      # The method responsible for the opposite direction is `#to_crystal`.
      #
      # Pass rules:
      # 1. The type is a value-type and passed by-value
      #   a. The type is copied? Then pass by-value.
      #   b. Else, pass by-reference.
      # 2. The type is passed by-reference
      #   a. Pass by-reference
      # 2. The type is passed by-pointer
      #   a. Pass by-pointer
      def to_cpp(type : Parser::Type) : Call::Result
        is_copied = is_type_copied?(type)
        is_ref = type.reference?
        is_val = type.pointer < 1
        ptr = type_pointer_depth(type)
        pass_by = TypeDatabase::PassBy::Original

        type_name = type_name_base(type)

        # If the method expects a value, but we don't copy its structure, we pass
        # a reference to it instead.
        if is_val && !is_copied
          is_ref = true
          ptr = 0
        end

        template = Template::None.new

        if rules = @db[type]?
          template = rules.to_cpp
          type_name = rules.cpp_type || type_name
          pass_by = rules.pass_by unless rules.pass_by.original?
          is_ref, ptr = reconfigure_pass_type(pass_by, is_ref, ptr)
        end

        if template.no_op?
          pass_by = type_config_to_pass_by(is_ref, ptr) if pass_by.original?
          template = conversion_template(pass_by, type, type_name)
        end

        Call::Result.new(
          type: type,
          type_name: type_name,
          reference: is_ref,
          pointer: ptr,
          conversion: template,
        )
      end

      # Computes a result for passing *type* from C++ to Crystal.
      # Also see `#pass_to_cpp` for the reverse direction.
      # See `#passthrough_to_crystal` to call Crystal from C++.
      #
      # Set *is_constructor* to `true` if this is a return-result of a method
      # and this method is a constructor.
      #
      # Pass rules:
      # 1. If *is_constructor* and the type is copied
      #   a. Then pass by-value.  (See `MethodName#generate` too)
      # 2. If pass by-reference
      #   a. Invoke the types copy-constructor and pass by-pointer.
      # 3. If pass by-value but the type is not copied
      #   a. Invoke the types copy-constructor and pass by-pointer.
      # 4. In all other cases
      #   a. Pass by-reference or by-pointer as defined by *type*.
      def to_crystal(type : Parser::Type, is_constructor = false) : Call::Result
        is_copied = is_type_copied?(type)
        is_ref = type.reference?
        ptr = type_pointer_depth(type)
        is_val = type.pointer < 1
        pass_by = TypeDatabase::PassBy::Original

        type_name = type_name_base(type)

        # TODO: Check for copy-constructor.
        if (is_constructor || is_val) && is_copied
          is_ref = false
          ptr = 0
          # Don't do pass_by magic here for this case, that's done in
          # `MethodName`.
        elsif is_ref || (is_val && !is_copied)
          is_ref = false
          ptr = 1

          pass_by = TypeDatabase::PassBy::Pointer
        elsif type.c_array?
          type = type.remove_all_extents
          is_ref = false
          ptr = 0
          pass_by = TypeDatabase::PassBy::Value
          template = "bindgen_array_to_slice(%)"
        end

        template = Template::None.new

        if rules = @db[type]?
          template ||= rules.from_cpp
          type_name = rules.cpp_type || type_name
          pass_by = rules.pass_by unless rules.pass_by.original?
          is_ref, ptr = reconfigure_pass_type(pass_by, is_ref, ptr)
        end

        if template.no_op?
          pass_by = type_config_to_pass_by(is_ref, ptr) if pass_by.original?
          template = conversion_template(pass_by, type, type_name)
        end

        Call::Result.new(
          type: type,
          type_name: type_name,
          reference: is_ref,
          pointer: ptr,
          conversion: template,
        )
      end

      # Takes *is_ref* and *ptr* and decides the described pass-by from it.
      private def type_config_to_pass_by(is_ref, ptr)
        if is_ref
          TypeDatabase::PassBy::Reference
        elsif ptr > 0
          TypeDatabase::PassBy::Pointer
        else
          TypeDatabase::PassBy::Value
        end
      end

      # Computes a result which is directly usable from C++ code, without
      # changes, and passes it through to crystal using conversion.
      #
      # The pass rules are similar to `#to_crystal`.  The primary
      # difference is that this version has no special handling of constructors.
      #
      # There is a second major difference:  This method always signals the C++
      # type to the outside, as received by C++ (Thus even ignoring
      # `rules.cpp_type`!).  It still follows the passing rules towards Crystal.
      def passthrough_to_crystal(type : Parser::Type)
        type_name = type_name_base(type)
        to_cr = to_crystal(type, is_constructor: false)

        Call::Result.new(
          type: type,
          type_name: type_name,
          reference: type.reference?,
          pointer: type_pointer_depth(type),
          conversion: to_cr.conversion,
        )
      end

      # Finds the conversion template to go from *type* to the desired target
      # type configuration.
      private def conversion_template(pass_by, type, type_name) : Template::Base
        original_ref = type.reference?
        original_ptr = type_pointer_depth(type) > 0

        @db.cookbook.find(type_name, original_ref, original_ptr, pass_by)
      end

      # Passes the *type* through without changes.
      def through(type : Parser::Type)
        type_name = type_name_base(type)

        Call::Result.new(
          type: type,
          type_name: type_name,
          reference: type.reference?,
          pointer: type_pointer_depth(type),
        )
      end
    end
  end
end
