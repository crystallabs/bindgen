module Bindgen
  module Processor
    # Processor removing methods that are to be ignored.
    #
    # Right now, methods can be ignored by any of:
    # 1. Ignoring a type the method uses as argument or result type
    # 2. By adding the name to `type.CLASS.ignore_methods`
    # 3. Methods using anonymous types are ignored, unless the type is named by
    #    a `typedef` (See `InstanceProperties`)
    # 4. Methods using unknown template instantiations are always ignored
    # 5. Conversion operators to types without rules
    # 6. Methods declared `[[deprecated]]`, if `ignore_deprecated` is set
    # 7. Methods using types nested in a template instantiation
    # 8. Operators Crystal can't name, like `operator->`
    class FilterMethods < Base
      include Graph::Visitor::MayDelete

      # Looks up a class by its name.
      private def class_by_name?(name : String) : Parser::Class?
        @db[name]?.try(&.graph_node).as?(Graph::Class).try(&.origin)
      end

      def visit_method(method : Graph::Method)
        remove_method(method) if filtered?(method.origin)
      end

      # Is the method *m* to be ignored by the rules above?  Processors adding
      # methods later, like `InstantiateContainers` and `Inheritance`, ask
      # this too, so a single `filter_methods` run suffices.
      def filtered?(m : Parser::Method) : Bool
        # Rule 1: Ignored types
        remove = m.filtered?(@db)

        # Rule 2: Explicitly ignored method
        if ignored = @db[m.class_name]?.try(&.ignore_methods)
          remove ||= ignored.includes?(m.name)
        end

        # Rule 3: Anonymous types
        remove ||= type_ignored?(m.class_name)
        remove ||= type_ignored?(m.return_type)
        remove ||= m.arguments.any? { |arg| type_ignored?(arg) }

        # Rule 4: Unknown template instantiations
        remove ||= unknown_template?(m.return_type)
        remove ||= m.arguments.any? { |arg| unknown_template?(arg) }

        # Rule 5: Conversion operators to types without rules, as their name
        # can be anything, like a pointer to a member
        remove ||= m.conversion_operator? && @db[m.return_type]?.nil?

        # Rule 6: Deprecated methods, overload by overload
        remove ||= @config.ignore_deprecated? && m.deprecated?

        # Rule 8: Operators Crystal can't name, like `operator->`
        remove ||= !m.supported_operator?

        # Rule 7: Types nested in a template instantiation, like
        # `QList<QString>::iterator`, which Crystal can't name
        remove ||= nested_in_instantiation?(m.return_type)
        remove ||= m.arguments.any? { |arg| nested_in_instantiation?(arg) }

        remove
      end

      # Removes the *method* from its parent.
      private def remove_method(method)
        Log.trace { "removing method #{method.diagnostics_path}" }
        parent = method.parent.as(Graph::Container)
        parent.nodes.delete method
      end

      # Checks if *type* is ignored.
      private def type_ignored?(type) : Bool
        # Log.notice { type.base_name } if type.is_a?(Parser::Type)
        @db.try_or(type, false) do |config|
          config.ignore? || (config.anonymous? && config.cpp_type.nil?)
        end
      end

      # Checks if *type* is nested in a template instantiation, like
      # `QList<QString>::iterator`, without rules of its own.
      private def nested_in_instantiation?(type : Parser::Type) : Bool
        return false if @db[type]?

        type.base_name.includes?(">::")
      end

      # Checks if *type* instantiates a template which is neither configured nor
      # a container.  Crystal can't name such a type.
      private def unknown_template?(type) : Bool
        return false unless templ = type.template
        return false if @db[type]?

        @config.containers.none?(&.class.== templ.base_name)
      end
    end
  end
end
