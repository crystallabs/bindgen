module Bindgen
  module Crystal
    # Functionality to get typenames of a `Parser::Type` in Crystal wrapper and
    # binding code.
    struct Typename
      spoved_logger

      def initialize(@db : TypeDatabase)
      end

      # Returns the full Crystal type-name of *result*.  If *expects_type* is
      # false, the type-name may appear in regular code, which affects how
      # pointers are formatted.
      def full(result : Call::Expression, *, expects_type = true)
        ptr = result.pointer
        ptr += 1 if result.reference
        nilable = "?" if result.nilable?

        if expects_type
          stars = "*" * ptr if ptr > 0
          "#{result.type_name}#{stars}#{nilable}"
        else
          prefix = "Pointer(" * ptr if ptr > 0
          suffix = ")" * ptr if ptr > 0
          "#{prefix}#{result.type_name}#{suffix}#{nilable}"
        end
      end

      # The type-name of *type* for use in a wrapper.
      # The returned tuple contains the name first, and secondly, if the
      # type shall be looked-up in the `lib Binding` (= `true`), or not.
      def wrapper(type : Parser::Type)
        rules = @db[type]?
        return {type.base_name, true} if rules.nil?

        # Only copied `struct`s reside in `Binding`!
        is_copied = rules.copy_structure?

        if name = rules.crystal_type
          {name, false}
        elsif name = rules.binding_type
          {name, is_copied}
        else
          {type.base_name, true}
        end
      end

      # Returns the qualified type-name of *type_name* from the output module.
      # If *in_lib* is `true`, the *type_name* is stored in `lib Binding`.  Else
      # it can is defined outside Binding, and thus doesn't need this prefix.
      def qualified(type_name : String, in_lib : Bool) : String
        if in_lib
          "#{Graph::LIB_BINDING}::#{type_name}"
        else
          type_name
        end
      end

      # The type-name of *type* for use in a binding.
      def binding(type : Parser::Type)
        rules = @db[type]?

        if rules.nil?
          logger.trace { "no rules found for: #{type.full_name}" }
          return {type.base_name, !type.builtin?}
        end

        # Copied structures end up in Binding
        in_lib = rules.copy_structure?
        # The `Void` check is required for `InstantiateContainers`, which marks
        # their binding types as built-in
        in_lib ||= !rules.kind.enum? && rules.binding_type != "Void" && !type.builtin?

        if name = rules.lib_type
          {name, in_lib}
        else
          {type.base_name, in_lib}
        end
      end
    end
  end
end
