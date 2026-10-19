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

      # Returns the body of a constructor configured in `depends_on:` of its
      # class, storing the selected arguments in the new object, or `nil` for
      # the default body.  A copy constructor stores the object it copies, so
      # the copy is destroyed before it, and in turn before its dependencies.
      # Only an object allocated as `CrystalGCWrapper` has room for them: the
      # constructors of copied, aggregate, union and `final` classes allocate
      # the class itself.
      private def depends_on_body(method : Parser::Method) : Call::Body?
        return unless rules = @db[method.class_name]?
        return if rules.depends_on.empty?

        indices = @db.selected_object_arguments(method, rules.depends_on)
        return if indices.empty?

        unless Cpp::MethodName.new(@db).gc_wrapper_constructor?(method)
          what = method.name.empty? ? "a constructor" : method.name
          Log.warn { "depends_on: of #{method.class_name} ignores #{what}: it doesn't allocate a CrystalGCWrapper" }
          return
        end

        CallBuilder::CppCall::DependsOnBody.new(indices)
      end
    end
  end
end
