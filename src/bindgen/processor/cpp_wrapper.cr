module Bindgen
  module Processor
    # Processor to wrap C++ as C `"extern"` functions.
    #
    # **Important**: This should be one of the last processors in the pipeline!
    class CppWrapper < Base
      include TypeHelper

      PLATFORM = Graph::Platform::Cpp

      def initialize(*args)
        super

        @wrapped_methods = Set(String).new
      end

      def visit_platform_specific(specific)
        super if specific.platforms.includes? PLATFORM
      end

      def visit_class(klass)
        warn_unmatched_depends_on(klass)
        super
      end

      def visit_method(method)
        return if method.calls[PLATFORM]?
        return if method.tag?(Graph::Method::EXPLICIT_BIND_TAG)

        mangled = method.mangled_name
        return if @wrapped_methods.includes?(mangled)
        @wrapped_methods << mangled

        klass = method.parent_class # Skip constructors on abstract class without shadow-subclass.
        return if klass.try(&.origin.abstract?) && method.origin.any_constructor? && !klass.try(&.cpp_sub_class)

        call = CallBuilder::CppCall.new(@db)
        wrapper = CallBuilder::CppWrapper.new(@db)

        if method.tag?(Graph::Method::SUPERCLASS_BIND_TAG)
          namer = Cpp::MethodName.new(@db)
          original_method = method.origin.origin || raise "BUG: Superclass method #{method.name} has no origin"
          method_name = namer.generate(original_method, "_self_", exact_member: true)
        end

        braces = method.origin.aggregate_constructor?
        body = depends_on_body(method.origin)
        target = call.build(method.origin, name: method_name, braces: braces, body: body)

        method.calls[PLATFORM] = wrapper.build(
          method: method.origin,
          class_name: cpp_class_name(method.origin.class_name), # An anonymous type by its typedef
          target: target,
        )
      end

      # Warns about the `depends_on:` patterns of *klass* matching none of its
      # constructors or methods.
      private def warn_unmatched_depends_on(klass)
        return unless rules = @db[klass.origin.name]?

        unmatched_patterns(klass, rules.depends_on).each do |pattern|
          Log.warn { "depends_on: of #{klass.origin.name} matches no method: #{pattern.source}.  Is it misspelt, or the method ignored or inherited?" }
        end
      end

      # Returns the body of a constructor or member method configured in
      # `depends_on:` of its class, storing the selected arguments in the
      # object, or `nil` for the default body.  A copy constructor stores the
      # object it copies, so the copy is destroyed before it, and in turn before
      # its dependencies.  A method replaces the dependencies the object had.
      # Only an object allocated as `CrystalGCWrapper` has room for them: the
      # constructors of copied, aggregate, union and `final` classes allocate
      # the class itself, and so methods of these classes are ignored too, as
      # are static methods, which have no object.
      private def depends_on_body(method : Parser::Method) : Call::Body?
        rules = inherited_rules(method.class_name, &.depends_on)
        return if rules.empty?

        indices = @db.selected_object_arguments(method, rules)
        return if indices.empty?

        if method.any_constructor?
          unless Cpp::MethodName.new(@db).gc_wrapper_constructor?(method)
            warn_ignored_depends_on(method, "it doesn't allocate a CrystalGCWrapper")
            return
          end

          CallBuilder::CppCall::DependsOnBody.new(indices)
        elsif !method.needs_instance? || method.signal?
          warn_ignored_depends_on(method, "it has no object")
        elsif !gc_wrapped_class?(method.class_name)
          warn_ignored_depends_on(method, "its objects aren't allocated as CrystalGCWrapper")
        else
          body = method.operator? ? CallBuilder::CppCall::OperatorBody.new : CallBuilder::CppCall::Body.new
          CallBuilder::CppCall::MethodDependsOnBody.new(indices, body)
        end
      end

      private def warn_ignored_depends_on(method : Parser::Method, reason : String) : Nil
        what = method.name.empty? ? "a constructor" : method.name
        Log.warn { "depends_on: of #{method.class_name} ignores #{what}: #{reason}" }
      end

      # Are all objects of *class_name* constructed from Crystal allocated as a
      # `CrystalGCWrapper`, which has room for dependencies?  Not those of a
      # copied, union or `final` class, nor of one with an aggregate
      # constructor, which allocates the class itself.
      private def gc_wrapped_class?(class_name : String) : Bool
        return false unless Cpp::MethodName.new(@db).gc_wrapper_class?(class_name)

        klass = @db[class_name]?.try(&.graph_node.as?(Graph::Class))
        !klass.try(&.nodes.any? { |node| node.as?(Graph::Method).try(&.origin.aggregate_constructor?) })
      end
    end
  end
end
