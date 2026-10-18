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
        target = call.build(method.origin, name: method_name, braces: braces)

        method.calls[PLATFORM] = wrapper.build(
          method: method.origin,
          class_name: cpp_class_name(method.origin.class_name), # An anonymous type by its typedef
          target: target,
        )
      end
    end
  end
end
