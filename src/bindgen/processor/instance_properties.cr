module Bindgen
  module Processor
    # Processor to add getter and setter methods for instance variables.
    class InstanceProperties < Base
      # Mapping from member name patterns to configurations.
      private alias VarConfig = TypeDatabase::InstanceVariableConfig::Collection

      def initialize(*args)
        super
      end

      def visit_class(klass : Graph::Class)
        # Skip `Impl` classes.  Also skip classes whose structures are copied
        # into `Binding`, as all fields are directly accessible anyway.
        return if klass.wrapped_class || @db[klass.name]?.try(&.copy_structure)

        var_config = @db.try_or(klass.name, VarConfig.new, &.instance_variables)

        klass.origin.each_field do |field|
          # Ignore private fields.  Also ignore all reference fields for now.
          next if field.private? || field.reference? || field.move?

          # For C arrays only built-in types are supported; user types will need
          # a custom `Slice`-like wrapper so that raw pointers are not returned.
          next if field.c_array? && (!field.builtin? || !field.c_complete_array?)

          pattern, config = lookup_member_config(var_config, field.name)
          next if config.ignore

          # C++'s `protected` is closer to Crystal's `private` than to `protected`
          access = field.protected? ?
            Parser::AccessSpecifier::Private : Parser::AccessSpecifier::Public
          method_name = config.rename ? field.name.gsub(pattern, config.rename) : field.name
          method_name = method_name.underscore
          field_type = config.nilable ? (field.make_pointer_nilable || field) : field

          add_getter(klass, access, field_type, field.name, method_name)
          add_setter(klass, access, field_type, field.name, method_name) unless field.const? || field.c_array?
        end

        super
      end

      # Looks up the configuration used for an instance variable.
      private def lookup_member_config(var_config, field_name)
        var_config.each do |key, config|
          return {key, config} if key.matches?(field_name)
        end

        {Util::FAIL_RX, TypeDatabase::InstanceVariableConfig.new}
      end

      # Builds a C++ wrapper method for an instance variable getter.  The `lib`
      # binding and the Crystal wrapper method are generated later.
      private def add_getter(klass, access, field_type, field_name, method_name)
        method_origin = Parser::Method.new(
          name: field_name,
          crystal_name: method_name,
          className: klass.origin.name,
          returnType: field_type,
          arguments: [] of Parser::Argument,
          type: Parser::Method::Type::MemberGetter,
          access: access,
          isConst: true,
        )

        method = Graph::Method.new(
          name: field_name,
          origin: method_origin,
          parent: klass,
        )

        body = GetterBody.new
        target = CallBuilder::CppCall.new(@db).build(method_origin, body: body)
        call = CallBuilder::CppWrapper.new(@db).build(method_origin, target)
        method.calls[Graph::Platform::Cpp] = call
      end

      # Code body for reading from a C++ instance variable.
      private class GetterBody < Call::Body
        def to_code(call : Call, _platform : Graph::Platform) : String
          code = call.name
          call.result.apply_conversion(code)
        end
      end

      # Builds a C++ wrapper method for an instance variable setter.  The `lib`
      # binding and the Crystal wrapper method are generated later.
      private def add_setter(klass, access, field_type, field_name, method_name)
        arg = Parser::Argument.new(field_name, field_type)

        method_origin = Parser::Method.new(
          name: field_name,
          crystal_name: method_name + "=",
          className: klass.origin.name,
          returnType: Parser::Type::VOID,
          arguments: [arg],
          type: Parser::Method::Type::MemberSetter,
          access: access,
        )

        method = Graph::Method.new(
          name: field_name,
          origin: method_origin,
          parent: klass,
        )

        body = SetterBody.new
        target = CallBuilder::CppCall.new(@db).build(method_origin, body: body)
        call = CallBuilder::CppWrapper.new(@db).build(method_origin, target)
        method.calls[Graph::Platform::Cpp] = call
      end

      # Code body for writing to a C++ instance variable.
      private class SetterBody < Call::Body
        def to_code(call : Call, _platform : Graph::Platform) : String
          code = call.arguments.first.call
          "#{call.name} = #{call.result.apply_conversion code}"
        end
      end
    end
  end
end
