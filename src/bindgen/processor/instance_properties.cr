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
        return if @db.try_or(klass.origin.name, false) { |rules| rules.copy_structure? && !structure_wrapped?(rules) }
        # An anonymous type can only be named in C++ through the `typedef` added
        # for a member of it, see `#add_anonymous_typedef`.
        return super if klass.origin.anonymous? && @db[klass.origin.name]?.try(&.cpp_type).nil?

        var_config = @db.try_or(klass.name, VarConfig.new, &.instance_variables)
        taken = method_signatures(klass)

        each_direct_field(klass) do |field, nested_access|
          # Ignore all reference fields for now.
          next if field.reference? || field.move?

          next if (field.c_array? || field.pointer_to_c_array?) && !@db.c_array_supported?(field)

          pattern, config = lookup_member_config(var_config, field.name)
          next if config.ignore

          # C++'s `protected` is closer to Crystal's `private` than to
          # `protected`
          access = nested_access.protected? ? Parser::AccessSpecifier::Private : Parser::AccessSpecifier::Public
          method_name = config.rename ? field.name.gsub(pattern, config.rename) : field.name
          method_name = method_name.underscore
          field_type = config.nilable ? (field.make_pointer_nilable || field) : field
          static = field.static?

          if @db[field]?.try(&.anonymous?)
            # Only non-const instance members by value are supported.
            next if static || field.const? || field.pointer > 0

            next unless field_klass = add_anonymous_typedef(klass, field)
            add_getter(klass, access, field_klass.as_type, field, static, method_name, AddressGetterBody.new)
            add_setter(klass, access, field_type, field, static, method_name)
          elsif static && field.const? && field.has_default? && (init = field.value)
            add_static_constant(klass, field, init)
          else
            # Methods win over property methods with the same Crystal name.
            add_getter(klass, access, field_type, field, static, method_name) unless taken.includes?({method_name, 0})
            unless field.const? || field.c_array? || taken.includes?({method_name + "=", 1})
              add_setter(klass, access, field_type, field, static, method_name)
            end
          end
        end

        super
      end

      # Does a wrapper, a class hosting the structure or a `kind: Struct`
      # wrapping it by value, hide the structure's fields?
      private def structure_wrapped?(rules : TypeDatabase::TypeConfig) : Bool
        structure_hosted?(rules) ||
          (rules.copy_structure? && rules.generate_wrapper? && rules.kind.struct? && rules.graph_node.is_a?(Graph::Class))
      end

      # Returns the Crystal names and argument counts of the methods of *klass*.
      private def method_signatures(klass)
        klass.nodes.compact_map do |node|
          if method = node.as?(Graph::Method)
            {method.origin.crystal_name, method.origin.arguments.size} unless method.origin.private?
          end
        end.to_set
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

          if field.name.empty? && @db[field]?.try(&.anonymous?)
            field_klass = @db[field.base_name].graph_node.as(Graph::Class)
            each_direct_field(field_klass, field_access, &block)
          else
            yield field, field_access
          end
        end
      end

      # Names the anonymous type of the *field* of *klass* in C++, through a
      # `typedef` of the field's `decltype`, and enables its wrapper.  Members
      # of the same type share the `typedef`.  Returns the type's class, or
      # `nil` if its wrapper can't be generated.
      private def add_anonymous_typedef(klass, field) : Parser::Class?
        rules = @db[field.base_name]
        field_klass = rules.graph_node.as(Graph::Class)
        return field_klass.origin if rules.cpp_type

        # A class nested inside an unwrapped class, like the type of an unnamed
        # member, isn't generated.
        parent = field_klass.parent.as?(Graph::Class)
        return if parent && !@db.try_or(parent.origin.name, true, &.generate_wrapper?)
        return unless typedef_name = rules.lib_type

        rules.cpp_type = typedef_name
        rules.generate_wrapper = true
        rules.generate_binding = true

        # On top of the class for C++, before its methods.
        host = Graph::PlatformSpecific.new(platform: Graph::Platform::Cpp)
        field_klass.nodes.unshift host
        host.parent = field_klass

        type_name = "decltype(#{cpp_class_name(klass.origin.name)}::#{field.name})"
        origin = Call::Result.new(
          type: field,
          type_name: type_name,
          reference: false,
          pointer: 0,
        )

        Graph::Alias.new(origin: origin, name: typedef_name, parent: host)
        field_klass.origin
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
      private def add_getter(klass, access, field_type, field, is_static, method_name, body = GetterBody.new)
        method_type = is_static ? Parser::Method::Type::StaticGetter : Parser::Method::Type::MemberGetter

        method_origin = Parser::Method.new(
          name: field.name,
          crystal_name: method_name,
          class_name: klass.origin.name,
          return_type: field_type,
          arguments: [] of Parser::Argument,
          type: method_type,
          access: access,
          const: true,
          doc: field.doc,
        )
        return if method_origin.filtered?(@db)

        method = Graph::Method.new(
          name: field.name,
          origin: method_origin,
          parent: klass,
        )

        target = CallBuilder::CppCall.new(@db).build(method_origin, body: body)
        call = CallBuilder::CppWrapper.new(@db).build(method_origin, target)
        method.calls[Graph::Platform::Cpp] = call
      end

      # Code body for reading from a C++ data member.
      class GetterBody < Call::Body
        def to_code(call : Call, platform : Graph::Platform) : String
          code = call.name
          call.result.apply_conversion(code)
        end
      end

      # Code body for taking the address of a C++ data member.
      private class AddressGetterBody < Call::Body
        def to_code(call : Call, platform : Graph::Platform) : String
          "&#{call.name}"
        end
      end

      # Builds a C++ wrapper method for a static or instance variable setter.
      # The `lib` binding and the Crystal wrapper method are generated later.
      private def add_setter(klass, access, field_type, field, is_static, method_name)
        method_type = is_static ? Parser::Method::Type::StaticSetter : Parser::Method::Type::MemberSetter
        arg = Parser::Argument.new(field.name, field_type)

        method_origin = Parser::Method.new(
          name: field.name,
          crystal_name: method_name + "=",
          class_name: klass.origin.name,
          return_type: Parser::Type::VOID,
          arguments: [arg],
          type: method_type,
          access: access,
          doc: field.doc,
        )
        return if method_origin.filtered?(@db)

        method = Graph::Method.new(
          name: field.name,
          origin: method_origin,
          parent: klass,
        )

        body = SetterBody.new
        target = CallBuilder::CppCall.new(@db).build(method_origin, body: body)
        call = CallBuilder::CppWrapper.new(@db).build(method_origin, target)
        method.calls[Graph::Platform::Cpp] = call
      end

      # Code body for writing to a C++ data member.
      class SetterBody < Call::Body
        def to_code(call : Call, platform : Graph::Platform) : String
          code = call.arguments.first.call
          "#{call.name} = #{call.result.apply_conversion code}"
        end
      end
    end
  end
end
