module Bindgen
  # Helper functionality for working with types.  Useful for all platforms.
  #
  # TODO: Turn into a `struct`?
  module TypeHelper
    # Builds a `Call::VariadicArgument`.  This is only applicable to directly
    # bound functions.
    def variadic_argument : Call::VariadicArgument
      Call::VariadicArgument.new(
        type: Parser::Type::VOID,
        type_name: "",
        name: "*va_args",
        call: "*va_args",
      )
    end

    # Builds a result passing-through *type* without modifications.
    def passthrough(type : Parser::Type)
      Call::Result.new(
        type: type,
        type_name: type.base_name,
        reference: type.reference?,
        pointer: type_pointer_depth(type),
      )
    end

    # Returns the pointer-depth without a reference of *type*.
    def type_pointer_depth(type : Parser::Type) : Int32
      depth = type.pointer
      depth -= 1 if type.reference?
      {depth, 0}.max
    end

    # Is *type* available in Crystal?  It will be if any of:
    # 1. The structure will be copied
    # 2. It's a built-in type
    # 3. It's an enumeration type
    #
    # Otherwise, `false` is returned.  If the *type* is not configured in the
    # type database, it defaults to `false`.
    def type_copied?(type) : Bool
      if rules = @db[type]?
        rules.copy_structure? || rules.builtin? || rules.kind.enum?
      else
        false
      end
    end

    # Returns the name of the class *class_name* in C++ code.  An anonymous
    # class can only be named through the `typedef` added by
    # `Processor::InstanceProperties`.
    def cpp_class_name(class_name : String) : String
      @db.try_or(class_name, class_name) do |rules|
        rules.cpp_type if rules.anonymous?
      end
    end

    # Is *type* a structure passed by value?  A `CrystalProc` passes it by
    # pointer instead, as a Crystal `Proc` doesn't follow the C ABI: the C ABI
    # passes a structure larger than 16 bytes indirectly, which a `Proc`
    # taking it by value reads as garbage.  This covers copied structures and
    # built-in `kind: Struct` types, like the `CrystalVariant` behind
    # `QVariant`.
    def proc_by_pointer?(type : Parser::Type) : Bool
      # A reference counts as a pointer in `Parser::Type`, like `const QVariant &`.
      return false if type.pointer > (type.reference? ? 1 : 0) || type.c_array?

      @db.try_or(type, false) do |rules|
        # C++ built-in types like `int` have `kind: Struct` rules too.
        structure = rules.copy_structure? || (rules.builtin? && rules.kind.struct? && !type.builtin?)
        structure && (rules.pass_by.original? || rules.pass_by.value?)
      end
    end

    # Does the Crystal wrapper class of the type described by *rules* host a
    # copy of the structure, instead of a pointer to it?  Its `#to_unsafe`
    # returns a pointer to the hosted structure then.
    #
    # This is not the case for a `kind: Struct` type, whose wrapper is a
    # Crystal `struct` returning the structure itself.
    def structure_hosted?(rules : TypeDatabase::TypeConfig) : Bool
      rules.copy_structure? && rules.generate_wrapper? && rules.kind.class? &&
        rules.graph_node.is_a?(Graph::Class)
    end

    # Helper for `#to_X`, configuring the type according to user-specified
    # rules.
    def reconfigure_pass_type(pass_by, is_ref, ptr)
      if pass_by.reference?
        is_ref = true
        ptr = 0
      elsif pass_by.pointer?
        is_ref = false
        ptr = {ptr, 1}.max
      elsif pass_by.value?
        is_ref = false
        ptr = 0
      end

      {is_ref, ptr}
    end
  end
end
