module Bindgen
  module CallBuilder
    # Builds a `Call` implementing a C++ member method, for overriding C++
    # virtual methods from Crystal.
    class CppMethod
      def initialize(@db : TypeDatabase)
      end

      # Builds the *method* of the shadow subclass *class_name*, calling the
      # Crystal override through *virtual_target*, a `CppToCrystalProc` call
      # taking the Crystal object, or *target*, the C++ implementation, if
      # there's no override.  *wrapped_class* is the class the subclass shadows,
      # whose pointer the Crystal object was bound to, see
      # `BindgenHelper.set_crystal_object`.
      def build(
        method : Parser::Method, target : Call?, virtual_target : Call,
        class_name : String? = nil, in_superclass = false, wrapped_class : String? = nil,
      )
        pass = Cpp::Pass.new(@db)
        class_name ||= method.class_name
        wrapped_class ||= method.class_name

        body = case
               when in_superclass
                 SuperclassBody.new(class_name, target || raise ArgumentError.new("Superclass method needs a target"))
               when target
                 VirtualBody.new(class_name, wrapped_class, target, virtual_target)
               else
                 PureBody.new(class_name, wrapped_class, virtual_target)
               end

        Call.new(
          origin: method,
          name: method.name,
          arguments: pass.arguments_from_cpp(method.arguments),
          result: pass.through(method.return_type),
          body: body,
        )
      end

      abstract class Body < Call::Body
        # The body, with the result type of the method as *result_type*, or
        # `nil` for `void`.
        abstract def code_body(const, call, platform, result_type)
        abstract def overriding? : Bool

        def to_code(call : Call, platform : Graph::Platform) : String
          formatter = Cpp::Format.new
          typer = Cpp::Typename.new
          func_result = typer.full(call.result)
          func_args = formatter.argument_list(call.arguments)

          # Returning a `void` from a void method generates a warning.
          result_type = func_result unless call.result.type.pure_void?
          const = "const " if call.origin.const?
          override = "override " if overriding?

          %[#{func_result} #{call.name}(#{func_args}) #{const}#{override}{\n] \
          %[#{code_body(const, call, platform, result_type)}\n] \
          %[}\n]
        end

        # The statements calling *target*, indented by *indent*.  See
        # `Cpp::Format#out_statements` for the out arguments of a call into
        # Crystal.
        protected def call_statements(target : Call, platform, result_type, indent : String) : String
          code = target.body.to_code(target, platform)
          lines = Cpp::Format.new.out_statements(target.arguments, code, result_type)
          lines.join("\n") { |line| "#{indent}#{line}" }
        end
      end

      # A body calling the Crystal override of a virtual method, if the
      # Crystal subclass has one, and the Crystal object still exists.
      abstract class OverridingBody < Body
        getter? overriding : Bool = true

        def initialize(@class : String, @wrapped_class : String, @virtual_target : Call)
        end

        # Declares `_self_`, and `_crystal_`, the Crystal object which
        # constructed the C++ object, see `BindgenHelper.set_crystal_object`,
        # or null once the GC collected it: the C++ object doesn't keep it
        # alive, only Crystal, or a `keep_alive:`, `depends_on:` or owner does.
        # The `Proc` of the override takes it, see `CppToCrystalProc#build`.
        protected def locals(const) : String
          crystal = CppToCrystalProc::CRYSTAL_OBJECT
          object = "const_cast<#{@wrapped_class} *>(static_cast<const #{@wrapped_class} *>(_self_))"

          %[  #{const}#{@class} *_self_ = this;\n] \
          %[  void *#{crystal} = #{@virtual_target.name}.isValid() ? bindgen_crystal_object(#{object}) : nullptr;\n]
        end

        # The condition to call the override under.
        protected def overridden : String
          CppToCrystalProc::CRYSTAL_OBJECT
        end
      end

      # Body for virtual targets.
      class VirtualBody < OverridingBody
        def initialize(klass : String, wrapped_class : String, @target : Call, virtual_target : Call)
          super(klass, wrapped_class, virtual_target)
        end

        def code_body(const, call, platform, result_type)
          %[#{locals(const)}] \
          %[  if (#{overridden}) {\n] \
          %[#{call_statements(@virtual_target, platform, result_type, "    ")}\n] \
          %[  } else {\n] \
          %[#{call_statements(@target, platform, result_type, "    ")}\n] \
          %[  }]
        end
      end

      # Body for superclass targets.
      class SuperclassBody < Body
        getter? overriding : Bool = false

        def initialize(@class : String, @target : Call)
        end

        def code_body(const, call, platform, result_type)
          call_statements(@target, platform, result_type, "  ")
        end
      end

      # Body for pure targets: there's no C++ implementation to fall back to.
      # Without an override, or once the Crystal object was collected, which
      # only happens to an object C++ kept without the binding knowing, the
      # program panics.
      class PureBody < OverridingBody
        def code_body(const, call, platform, result_type)
          %[#{locals(const)}] \
          %[  if (bindgen_likely(#{overridden})) {\n] \
          %[#{call_statements(@virtual_target, platform, result_type, "    ")}\n] \
          %[  } else if (#{@virtual_target.name}.isValid()) {\n] \
          %[    bindgen_fatal_panic("The Crystal object implementing pure method #{call.origin.class_name}::#{call.name} was collected");\n] \
          %[  } else {\n] \
          %[    bindgen_fatal_panic("No implementation for pure method #{call.origin.class_name}::#{call.name}");\n] \
          %[  }]
        end
      end
    end
  end
end
