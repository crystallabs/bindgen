module Bindgen
  module CallBuilder
    # Builds a `Call` implementing a C++ member method, for overriding C++
    # virtual methods from Crystal.
    class CppMethod
      def initialize(@db : TypeDatabase)
      end

      def build(
        method : Parser::Method, target : Call?, virtual_target : Call,
        class_name : String? = nil, in_superclass = false,
      )
        pass = Cpp::Pass.new(@db)
        class_name ||= method.class_name

        body = case
               when in_superclass
                 SuperclassBody.new(class_name, target.not_nil!)
               when target
                 VirtualBody.new(class_name, target, virtual_target)
               else
                 PureBody.new(class_name, virtual_target)
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
        abstract def code_body(const, call, platform, prefix)
        abstract def overriding? : Bool

        def to_code(call : Call, platform : Graph::Platform) : String
          formatter = Cpp::Format.new
          typer = Cpp::Typename.new
          func_result = typer.full(call.result)
          func_args = formatter.argument_list(call.arguments)

          # Returning a `void` from a void method generates a warning.
          prefix = "return " unless call.result.type.pure_void?
          const = "const " if call.origin.const?
          override = "override " if overriding?

          %[#{func_result} #{call.name}(#{func_args}) #{const}#{override}{\n] \
          %[#{code_body(const, call, platform, prefix)}\n] \
          %[}\n]
        end
      end

      # Body for virtual targets.
      class VirtualBody < Body
        getter? overriding : Bool = true

        def initialize(@class : String, @target : Call, @virtual_target : Call)
        end

        def code_body(const, call, platform, prefix)
          %[  #{const}#{@class} *_self_ = this;\n] \
          %[  if (#{@virtual_target.name}.isValid()) {\n] \
          %[    #{prefix}#{@virtual_target.body.to_code(@virtual_target, platform)};\n] \
          %[  } else {\n] \
          %[    #{prefix}#{@target.body.to_code(@target, platform)};\n] \
          %[  }]
        end
      end

      # Body for superclass targets.
      class SuperclassBody < Body
        getter? overriding : Bool = false

        def initialize(@class : String, @target : Call)
        end

        def code_body(const, call, platform, prefix)
          %[  #{prefix}#{@target.body.to_code(@target, platform)};]
        end
      end

      # Body for pure targets.
      class PureBody < Body
        getter? overriding : Bool = true

        def initialize(@class : String, @virtual_target : Call)
        end

        def code_body(const, call, platform, prefix)
          %[  #{const}#{@class} *_self_ = this;\n] \
          %[  if (bindgen_likely(#{@virtual_target.name}.isValid())) {\n] \
          %[    #{prefix}#{@virtual_target.body.to_code(@virtual_target, platform)};\n] \
          %[  } else {\n] \
          %[    bindgen_fatal_panic("No implementation for pure method #{call.origin.class_name}::#{call.name}");\n] \
          %[  }]
        end
      end
    end
  end
end
