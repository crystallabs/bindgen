module Bindgen
  module Processor
    # Processor to add getter and setter methods for static and instance
    # variables.
    class InstanceProperties < Base
      include TypeHelper

      # Mapping from member name patterns to configurations.
      private alias VarConfig = TypeDatabase::InstanceVariableConfig::Collection

      def initialize(*args)
        super
      end

      def visit_class(klass : Graph::Class)
        # Skip `Impl` classes.  Also skip classes whose structures are copied
        # into `Binding`, as all fields are directly accessible anyway, unless
        # they're hidden inside a wrapper class.
        return if klass.wrapped_class
        return if @db.try_or(klass.origin.name, false) { |rules| rules.copy_structure? && !structure_hosted?(rules) }

        var_config = @db.try_or(klass.name, VarConfig.new, &.instance_variables)

        each_direct_field(klass) do |field, nested_access|
          # Ignore all reference fields for now.
          next if field.reference? || field.move?

          # For C arrays only built-in types are supported; user types will need
          # a custom `Slice`-like wrapper so that raw pointers are not returned.
          next if field.c_array? && (!field.builtin? || !field.c_complete_array?)
          next if field.pointer_to_c_array? # Not supported yet

          pattern, config = lookup_member_config(var_config, field.name)
          next if config.ignore

          # C++'s `protected` is closer to Crystal's `private` than to
          # `protected`
          access = nested_access.protected? ? Parser::AccessSpecifier::Private : Parser::AccessSpecifier::Public
          method_name = config.rename ? field.name.gsub(pattern, config.rename) : field.name
          method_name = method_name.underscore
          field_type = config.nilable ? (field.make_pointer_nilable || field) : field
          static = field.static?

          if static && field.const? && field.has_default? && (init = field.value)
            add_static_constant(klass, field, init)
          else
            add_getter(klass, access, field_type, field.name, static, method_name)
            add_setter(klass, access, field_type, field.name, static, method_name) unless field.const? || field.c_array?
          end
        end

        super
      end

      # Looks up the configuration used for a data member.
      private def lookup_member_config(var_config, field_name)
        var_config.each do |key, config|
          return {key, config} if key.matches?(field_name)
        end

        {Util::FAIL_RX, TypeDatabase::InstanceVariableConfig.new}
      end

      # Iterates through each direct data member of a structure.  Recursively
      # descends into fields inside nested anonymous types that don't name a
      # member.
      private def each_direct_field(
        klass, nested_access = Parser::AccessSpecifier::Public,
        &block : Parser::Field, Parser::AccessSpecifier ->
      )
        klass.origin.fields.each do |field|
          next if field.private? # Ignore private fields.
          # Public fields nested inside protected members are still protected.
          field_access = nested_access.protected? ? nested_access : field.access

          if @db[field]?.try(&.anonymous?)
            if field.name.empty?
              field_klass = @db[field.base_name].graph_node.as(Graph::Class)
              each_direct_field(field_klass, field_access, &block)
            end
          else
            yield field, field_access
          end
        end
      end

      # Builds a static constant for the *field* in the given *klass*, whose
      # initializer is *value*.
      private def add_static_constant(klass, field, value)
        # Retype the constant value if possible (JSON deserialization may
        # produce a value of a larger type than the actual field type).
        type = Crystal::Type.new(@db)
        typed_value = type.convert(value, field) || value
        Graph::Constant.new(
          name: field.name.underscore.upcase,
          parent: klass.platform_specific(Graph::Platform::Crystal),
          value: typed_value,
        )
      end

      # Builds a C++ wrapper method for a static or instance variable getter.
      # The `lib` binding and the Crystal wrapper method are generated later.
      private def add_getter(klass, access, field_type, field_name, is_static, method_name)
        method_type = is_static ? Parser::Method::Type::StaticGetter : Parser::Method::Type::MemberGetter

        method_origin = Parser::Method.new(
          name: field_name,
          crystal_name: method_name,
          class_name: klass.origin.name,
          return_type: field_type,
          arguments: [] of Parser::Argument,
          type: method_type,
          access: access,
          const: true,
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

      # Code body for reading from a C++ data member.
      private class GetterBody < Call::Body
        def to_code(call : Call, platform : Graph::Platform) : String
          code = call.name
          call.result.apply_conversion(code)
        end
      end

      # Builds a C++ wrapper method for a static or instance variable setter.
      # The `lib` binding and the Crystal wrapper method are generated later.
      private def add_setter(klass, access, field_type, field_name, is_static, method_name)
        method_type = is_static ? Parser::Method::Type::StaticSetter : Parser::Method::Type::MemberSetter
        arg = Parser::Argument.new(field_name, field_type)

        method_origin = Parser::Method.new(
          name: field_name,
          crystal_name: method_name + "=",
          class_name: klass.origin.name,
          return_type: Parser::Type::VOID,
          arguments: [arg],
          type: method_type,
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

      # Code body for writing to a C++ data member.
      private class SetterBody < Call::Body
        def to_code(call : Call, platform : Graph::Platform) : String
          code = call.arguments.first.call
          "#{call.name} = #{call.result.apply_conversion code}"
        end
      end
    end
  end
end
