module Bindgen
  module Cpp
    # Generator for calling methods by their name.
    struct MethodName
      GLOBAL_SCOPE = "::"

      include TypeHelper

      def initialize(@db : TypeDatabase)
      end

      # Generates the C++ *method* name.
      #
      # If this kind of method requires an instance, it will use *self_var* and
      # use `->` on it.
      #
      # If the *method* is any constructor, and the type is copied, the
      # constructor will be called without `new`, effectively returning a value.
      # Otherwise, a normal `new` is used to return a pointer.  An aggregate
      # constructor allocates the class itself, so that the caller can
      # brace-initialize it.  So do the constructors of a C++ union or `final`
      # class, which can't be wrapped as it can't be inherited from.
      #
      # If *exact_member* is true and *method* is a member method, the qualified
      # method is called, bypassing dynamic lookup.
      def generate(
        method : Parser::Method, self_var : String,
        type : Parser::Method::Type? = nil, exact_member = false,
      )
        type ||= method.type
        case type
        when .any_constructor?
          if type_copied?(method.class_name)
            "bg_deref<#{method.class_name}>"
          elsif gc_wrapper_constructor?(method, type) # Support shadow sub-classing.
            name = class_name_for_new(method.class_name)
            @db.cookbook.constructor_name(method.name, name)
          else
            @db.cookbook.plain_constructor_name(method.name, cpp_class_name(method.class_name))
          end
        when .member_method?, .member_getter?, .member_setter?, .signal?, .operator?,
             .conversion_operator?
          if exact_member
            "#{self_var}->#{qualified method}"
          else
            "#{self_var}->#{method.name}"
          end
        when .static?
          qualified(method)
        else
          raise "BUG: Missing case for method type #{method.type.inspect}"
        end
      end

      # Is *method* a constructor allocating a `CrystalGCWrapper` of its class,
      # instead of the class itself?  See `#generate`.
      def gc_wrapper_constructor?(method : Parser::Method, type : Parser::Method::Type = method.type) : Bool
        type.any_constructor? && !type_copied?(method.class_name) &&
          !type.aggregate_constructor? && !uninheritable?(method.class_name)
      end

      # Returns the qualified name of a method.
      private def qualified(method)
        if method.class_name == GLOBAL_SCOPE
          "::#{method.name}"
        else
          "#{method.class_name}::#{method.name}"
        end
      end

      # Finds *class_name* in the graph and checks if it's a C++ union or a
      # `final` class.
      private def uninheritable?(class_name) : Bool
        @db.try_or(class_name, false) do |rules|
          rules.graph_node.as?(Graph::Class).try { |k| k.origin.cpp_union? || k.origin.final? }
        end
      end

      # Finds *class_name* in the graph and checks if it's shadow sub-classed in
      # C++.  If so, returns the name of the shadow class, otherwise the name
      # of the class in C++.
      private def class_name_for_new(class_name)
        @db.try_or(class_name, cpp_class_name(class_name)) do |rules|
          rules.graph_node.as?(Graph::Class).try(&.cpp_sub_class)
        end
      end
    end
  end
end
