module Bindgen
  module Cpp
    # C++ type-name generation logic.
    struct Typename
      # Formats the type in *result* in C++ style.
      #
      # A pointer or reference to a C array is spelled through `bindgen_type`,
      # as C++ can't declare e.g. a variable of type `int (*)[4]` by appending
      # its name to the type.
      def full(result : Call::Expression) : String
        type = result.type

        if type.array_pointer > 0
          outer = type.array_pointer - (result.reference ? 1 : 0)
          inner = result.pointer - type.extents.size - outer
          array = full(result.type_name, type.const?, inner, false, type.extents)
          "bindgen_type<#{array}> #{"*" * outer}#{"&" if result.reference}"
        else
          full(result.type_name, type.const?, result.pointer, result.reference, type.extents)
        end
      end

      # :ditto:
      #
      # The stars of *pointer* include those of the *array_pointer*
      # indirections applying to the whole array, like in `int (*)[4]`.
      def full(base_name : String, const, pointer, is_reference, extents = nil, array_pointer = 0) : String
        if array_pointer > 0 && extents
          return full_array_pointer(base_name, const, pointer, is_reference, extents, array_pointer)
        end

        String.build do |b|
          b << "const " if const
          b << base_name

          stars = "*" * pointer if pointer > 0
          subscripts = extents.map { |v| "[#{v unless v.zero?}]" }.join unless extents.nil? || extents.empty?
          ref = "&" if is_reference

          b << ' ' if stars || ref || subscripts
          b << stars << subscripts << ref
        end
      end

      # Formats a pointer or reference to a C array, like `int *(*)[4]`.
      private def full_array_pointer(base_name, const, pointer, is_reference, extents, array_pointer) : String
        outer = array_pointer - (is_reference ? 1 : 0)
        element = full(base_name, const, pointer - outer, false)
        subscripts = extents.join { |v| "[#{v unless v.zero?}]" }

        "#{element}#{' ' unless element.ends_with?('*')}(#{"*" * outer}#{"&" if is_reference})#{subscripts}"
      end

      # Formats many *results*.
      def full(results : Enumerable(Call::Expression)) : Array(String)
        results.map { |result| full(result) }
      end

      # Generates the C++ type name of a *template* class with the given
      # template type *arguments*.
      def template_class(template : String, arguments : Enumerable(String)) : String
        String.build do |b|
          b << template << '<'

          first = true
          needs_space = false
          arguments.each do |arg|
            b << ", " unless first
            b << arg
            first = false
            needs_space = arg.ends_with?('>')
          end

          b << ' ' if needs_space
          b << '>'
        end
      end
    end
  end
end
