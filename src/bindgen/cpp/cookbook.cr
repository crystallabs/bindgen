module Bindgen
  module Cpp
    # The cookbook contains snippets for the C++ and C platforms.
    #
    # The `TypeDatabase` stores which cookbook to use.  Don't `.new` your own.
    #
    # Which cookbook is used is configured by the user through the `platform:`
    # setting.  See `Configuration#platform` for the code, and `TEMPLATE.yml`
    # for user-facing documentation.
    #
    # The functions all return a `Template::Basic` when conversion is
    # necessary, and `Template::None` otherwise.
    abstract class Cookbook
      # Finds and creates a `Cookbook` by name.
      def self.create_by_name(name) : Cookbook
        case name.downcase
        when "boehmgc-cpp", "boehmgc-cxx", "boehmgc-c++", "cpp", "cxx", "c++"
          BoehmGcCppCookbook.new
        when "bare-cpp", "bare-cxx", "bare-c++"
          BareCppCookbook.new
        when "boehmgc-c", "c"
          BoehmGcCCookbook.new
        when "bare-c"
          BareCCookbook.new
        else
          raise "Unknown cookbook name #{name.inspect}"
        end
      end

      # Finds the template to pass *type* as-is as *pass_by*.  The returned
      # template takes an expression returning something of *type* and turns it
      # into something that can be *pass_by*'d on.
      def find(type : Parser::Type, pass_by : TypeDatabase::PassBy) : Template::Base
        is_ref = type.reference?
        is_ptr = !is_ref && type.pointer > 0

        find(type.base_name, is_ref, is_ptr, pass_by)
      end

      # Same, but provides an override of *type*s reference and pointer
      # qualification.
      def find(base_name : String, is_reference, is_pointer, pass_by : TypeDatabase::PassBy) : Template::Base
        template_string = case pass_by
        when .original?
          nil # No conversion required.
        when .reference?
          if is_reference # Reference -> Referene
            nil
          elsif is_pointer # Pointer -> Reference
            pointer_to_reference(base_name)
          else # Value -> Reference
            value_to_reference(base_name)
          end
        when .pointer?
          if is_reference # Reference -> Pointer
            reference_to_pointer(base_name)
          elsif is_pointer # Pointer -> Pointer
            nil
          else # Value -> Pointer
            value_to_pointer(base_name)
          end
        when .value?
          if is_reference # Reference -> Value
            reference_to_value(base_name)
          elsif is_pointer # Pointer -> Value
            pointer_to_value(base_name)
          else # Value -> Value
            nil
          end
        end

        Template.from_string(template_string, simple: true)
      end

      # Provides a template to convert a value to a pointer.
      abstract def value_to_pointer(type : String) : String?

      # Provides a template to convert a value to a reference.
      abstract def value_to_reference(type : String) : String?

      # Provides a template to convert a reference to a pointer.
      abstract def reference_to_pointer(type : String) : String?

      # Provides a template to convert a reference to a value.
      abstract def reference_to_value(type : String) : String?

      # Provides a template to convert a pointer to a reference.
      abstract def pointer_to_reference(type : String) : String?

      # Provides a template to convert a pointer to a value.
      abstract def pointer_to_value(type : String) : String?

      # How to call the constructor *method* of *class_name*.
      abstract def constructor_name(method_name : String, class_name : String) : String
    end

    # Cookbook for the C++ language using Boehm-GC for memory management.
    #
    # Configuration name is `bare-cpp`.
    class BareCppCookbook < Cookbook
      def constructor_name(method_name : String, class_name : String) : String
        "new #{class_name}"
      end

      def value_to_pointer(type : String) : String?
        "new #{type} (%)"
      end

      def value_to_reference(type : String) : String?
        nil # Nothing to do
      end

      def reference_to_pointer(type : String) : String?
        "&(%)"
      end

      def reference_to_value(type : String) : String?
        nil # Nothing to do
      end

      def pointer_to_reference(type : String) : String?
        "*(%)"
      end

      def pointer_to_value(type : String) : String?
        "*(%)"
      end
    end

    # Cookbook for the C language using Boehm-GC for memory management.
    #
    # Configuration name is `bare-c`.
    #
    # References are supported, although they shouldn't occur.
    class BareCCookbook < Cookbook
      def constructor_name(method_name : String, class_name : String) : String
        method_name
      end

      def value_to_pointer(type : String) : String?
        "memcpy(malloc(sizeof(#{type})), %, sizeof(#{type}))"
      end

      def value_to_reference(type : String) : String?
        nil # Nothing to do
      end

      def reference_to_pointer(type : String) : String?
        "&(%)"
      end

      def reference_to_value(type : String) : String?
        nil # Nothing to do
      end

      def pointer_to_reference(type : String) : String?
        "*(%)"
      end

      def pointer_to_value(type : String) : String?
        "*(%)"
      end
    end

    # Cookbook for the C++ language using Boehm-GC for memory management.
    #
    # Configuration name is `boehmgc-cpp`, aliased as `cpp` for convenience.
    class BoehmGcCppCookbook < BareCppCookbook
      def constructor_name(method_name : String, class_name : String) : String?
        "new (UseGC) #{class_name}"
      end

      def value_to_pointer(type : String) : String?
        "new (UseGC) #{type} (%)"
      end
    end

    # Cookbook for the C language using Boehm-GC for memory management.
    #
    # Configuration name is `boehmgc-c`, aliased as `c` for convenience.
    #
    # References are supported, although they shouldn't occur.
    class BoehmGcCCookbook < BareCCookbook
      # Rely on `#finalize` for this.
      # def constructor_name(method_name : String, class_name : String)

      def value_to_pointer(type : String) : String?
        "memcpy(GC_malloc(sizeof(#{type})), %, sizeof(#{type}))"
      end
    end
  end
end
