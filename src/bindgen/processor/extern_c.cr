module Bindgen
  module Processor
    # Checks if a method require a C/C++ wrapper.  If not, marks the method to
    # bind directly to the target method instead of writing a "trampoline"
    # wrapper in C++.
    #
    # A method can be bound directly if all of these are true:
    #
    # 1. It uses the C ABI (`extern "C"`)
    # 2. No argument uses a `to_cpp` converter
    # 3. The return type doesn't use a `from_cpp` converter
    #
    # Additionally, these rules must be met:
    #
    # 4. No calls for `CrystalBinding` nor `Cpp` are set
    # 5. `Graph::Method::EXPLICIT_BIND_TAG` is not already set
    #
    # If any of this is false, the method is left alone.
    class ExternC < Base
      PLATFORM = Graph::Platform::Crystal

      def visit_platform_specific(specific)
        super if specific.platforms.includes?(PLATFORM)
      end

      def visit_method(method)
        return unless method.origin.extern_c? # Rule 1

        return if method.tag?(Graph::Method::EXPLICIT_BIND_TAG)  # Rule 5
        unless method.tag?(Graph::Method::REMOVABLE_BINDING_TAG) # Rule 4
          return if method.calls[Graph::Platform::CrystalBinding]?
          return if method.calls[Graph::Platform::Cpp]?
        end

        # Conversion checks
        pass = Cpp::Pass.new(@db)
        any_arg_uses_conversion = method.origin.arguments.any? do |arg|
          !pass.to_cpp(arg).conversion.no_op?
        end

        return if !pass.to_crystal(method.origin.return_type).conversion.no_op? # Rule 3
        return if any_arg_uses_conversion                                       # Rule 2

        # If we end up here, the method can be bound to directly.
        method.set_tag(Graph::Method::EXPLICIT_BIND_TAG, method.origin.name)

        method.calls.delete Graph::Platform::CrystalBinding
        method.calls.delete Graph::Platform::Cpp
      end
    end
  end
end
