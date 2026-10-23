module Bindgen
  module CallBuilder
    # Builds a `Call` calling a C/C++ function.
    class CppCall
      include TypeHelper

      def initialize(@db : TypeDatabase)
      end

      def build(
        method : Parser::Method, self_var = "_self_", body : Call::Body? = nil,
        name : String? = nil, braces : Bool = false,
      )
        pass = Cpp::Pass.new(@db)

        if method.operator?
          name ||= self_var
          body ||= OperatorBody.new
        elsif method.free_function?
          name ||= method.name
          body ||= FreeFunctionBody.new(self_var)
        else
          method_name = Cpp::MethodName.new(@db)
          name ||= method_name.generate(method, self_var)
          # A copied type is built by `bg_deref<T>`, see `Cpp::MethodName`.
          body ||= if !braces
                     Body.new
                   elsif type_copied?(method.class_name)
                     BraceBody.new(method.class_name)
                   else
                     BraceBody.new
                   end
        end

        Call.new(
          origin: method,
          name: name,
          arguments: pass.arguments_to_cpp(method.arguments),
          result: pass.to_crystal(method.return_type, is_constructor: method.any_constructor?),
          body: body,
        )
      end

      # Body used by `CppCall` and `CppMethodCall`.
      class Body < Call::Body
        def to_code(call : Call, platform : Graph::Platform) : String
          pass_args = call.arguments.map(&.call).join(", ")
          code = %[#{call.name}(#{pass_args})]
          call.result.apply_conversion(code)
        end
      end

      # Body of a constructor allocating a `CrystalGCWrapper`, which stores the
      # arguments at *indices* in the new object through `bindgen_depends_on`,
      # so the GC destroys it before them.  See `depends_on:`.
      class DependsOnBody < Call::Body
        def initialize(@indices : Array(Int32))
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          pass_args = call.arguments.map(&.call).join(", ")
          dependencies = DependsOnBody.dependencies(call, @indices)
          code = %[bindgen_depends_on(#{call.name}(#{pass_args}), {#{dependencies}})]
          call.result.apply_conversion(code)
        end

        # The arguments at *indices* of *call*, as pointers.
        def self.dependencies(call : Call, indices : Array(Int32)) : String
          indices.join(", ") do |index|
            arg = call.arguments[index]
            arg.reference ? "&#{arg.name}" : arg.name
          end
        end
      end

      # Body of a member method, which replaces the dependencies of the object
      # *self_var* by the arguments at *indices* through `bindgen_depends_on`,
      # and then runs the call of *body*.  See `depends_on:`.
      class MethodDependsOnBody < Call::Body
        def initialize(@indices : Array(Int32), @body : Call::Body, @self_var = "_self_")
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          dependencies = DependsOnBody.dependencies(call, @indices)
          code = @body.to_code(call, platform)
          %[(bindgen_depends_on(#{@self_var}, {#{dependencies}}), #{code})]
        end
      end

      # Body used for brace initialization.  The braces are put right behind
      # the call name, which initializes the aggregate in place.
      #
      # If a *value_type* is given, the call name is a function instead, which
      # is called with a brace-initialized *value_type*.  This copies or moves
      # the value.
      class BraceBody < Call::Body
        def initialize(@value_type : String? = nil)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          pass_args = call.arguments.map(&.call).join(", ")
          code = if value_type = @value_type
                   %[#{call.name}(#{value_type} {#{pass_args}})]
                 else
                   %[#{call.name} {#{pass_args}}]
                 end

          call.result.apply_conversion(code)
        end
      end

      # Body invoking a free function of `member_functions` with the object as
      # its first argument: `qHash(*_self_, seed)`.
      class FreeFunctionBody < Call::Body
        def initialize(@self_var : String)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          pass_args = ["*#{@self_var}"].concat(call.arguments.map(&.call)).join(", ")
          call.result.apply_conversion(%[#{call.name}(#{pass_args})])
        end
      end

      # Body invoking a C++ operator.
      class OperatorBody < Call::Body
        def to_code(call : Call, platform : Graph::Platform) : String
          case call.origin.binding_operator_name
          when "call"
            pass_args = call.arguments.map(&.call).join(", ")
            code = %[(*#{call.name})(#{pass_args})]
          when "succ", "pred", "plus", "neg", "deref", "bit_not", "not"
            op = call.origin.name[8..] # Remove `operator` prefix
            code = %[#{op}(*#{call.name})]
          when "post_succ", "post_pred"
            op = call.origin.name[8..]
            code = %[(*#{call.name})#{op}]
          when "at"
            pass_arg = call.arguments.first.call
            code = %{(*#{call.name})[#{pass_arg}]}
          else # remaining binary operators
            op = call.origin.name[8..]
            pass_arg = call.arguments.first.call
            code = %[(*#{call.name}) #{op} (#{pass_arg})]
          end

          # A conversion like `%.count()` applies to the whole expression.
          call.result.apply_conversion("(#{code})")
        end
      end
    end
  end
end
