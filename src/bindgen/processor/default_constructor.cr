module Bindgen
  module Processor
    # Checks that all default-constructible classes have a default constructor
    # defined.
    class DefaultConstructor < Base
      def visit_class(klass : Graph::Class)
        return unless klass.wrapped_class.nil? # Skip `Impl` classes

        build_aggregate_constructor(klass) if needs_aggregate_constructor?(klass.origin)
        build_default_constructor(klass) if needs_default_constructor?(klass)
      end

      # Builds an argument-less constructor for *klass*.
      private def build_default_constructor(klass : Graph::Class)
        ctor = Parser::Method.build(
          type: Parser::Method::Type::Constructor,
          name: "",
          class_name: klass.origin.name,
          arguments: [] of Parser::Argument,
          return_type: Parser::Type::EMPTY,
        )

        Graph::Method.new(
          origin: ctor,
          name: ctor.name,
          parent: klass,
        )
      end

      # Builds an aggregate constructor for *klass*.  The constructor respects
      # exposed default values of the class fields.
      private def build_aggregate_constructor(klass : Graph::Class)
        fields = klass.origin.fields.reject(&.static?)
        args = fields.map do |field|
          Parser::Argument.new(field.name, field, field.has_default?, field.value)
        end

        ctor = Parser::Method.build(
          type: Parser::Method::Type::AggregateConstructor,
          name: "",
          class_name: klass.origin.name,
          arguments: args,
          return_type: Parser::Type::EMPTY,
        )

        Graph::Method.new(
          origin: ctor,
          name: ctor.name,
          parent: klass,
        )
      end

      # Checks if *klass* needs a default constructor; that is, none of its
      # constructors can be called without arguments.
      private def needs_default_constructor?(klass : Graph::Class)
        # Only allow default-constructible classes.
        return false unless klass.origin.has_default_constructor?

        klass.nodes.none? do |node|
          node.is_a?(Graph::Method) && node.origin.any_default_constructor?
        end
      end

      # Checks if *klass* needs an aggregate constructor.
      #
      # 1. The class is not empty.
      # 2. All fields of the class are public.
      # 3. None of the fields have default values.
      # 4. None of the fields use anonymous types.
      # 5. The class is not polymorphic.
      # 6. The class has no bases.
      # 7. The class has no user-declared constructors.
      # 8. The class is not a C++ union.
      #
      # These are the rules of an aggregate common to C++11 through C++20, so
      # that the constructor compiles no matter which standard the wrapper is
      # built with.  Rule 7 is the one of C++20: Up to C++17, a constructor
      # declared as `= default` or `= delete` is allowed.
      private def needs_aggregate_constructor?(klass : Parser::Class)
        fields = klass.fields.reject(&.static?)

        allowed = !fields.empty? # 1.
        allowed &&= fields.all? do |field|
          field.public? &&                 # 2.
            !field.has_default? &&         # 3.
            !@db[field]?.try(&.anonymous?) # 4.
        end

        allowed &&= !klass.has_virtual_methods? # 5.
        allowed &&= klass.bases.empty?          # 6.

        allowed &&= !klass.has_user_declared_constructor? # 7.
        allowed &&= klass.methods.none? do |method|
          !method.builtin? && method.any_constructor? # 7., for generated classes
        end
        allowed &&= !klass.cpp_union? # 8.

        allowed
      end
    end
  end
end
