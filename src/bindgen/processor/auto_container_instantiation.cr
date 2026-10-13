module Bindgen
  module Processor
    # Processor analyzing the input, and then reconfigures the list of wrapped
    # container types (sequential and associative) to reflect all those used.
    #
    # Elimnates the need to build the list manually.
    #
    # This processor must be run before `InstantiateContainers`.
    class AutoContainerInstantiation < Base
      def visit_method(method : Graph::Method)
        m = method.origin

        try_add_container_type m.return_type
        try_add_container_type @db.resolve_aliases m.return_type

        m.arguments.each do |argument|
          try_add_container_type argument
          try_add_container_type @db.resolve_aliases argument
        end
      end

      # Checks if *type* is a configured container type.  If so, record its
      # instantiation.
      private def try_add_container_type(type)
        # Skip if we're to ignore this whole type.
        return if @db.try_or(type, false, &.ignore?)

        templ = type.template
        return if templ.nil? # Has to be a template type

        container = @config.containers.find(&.class.== templ.base_name)
        return if container.nil? # Not a configured container type

                  # Check for the correct amount of template arguments.  There may be more
                  # than those arguments, which are usually allocators.
        arg_count = container_type_arguments(container.type)
        return if templ.arguments.size < arg_count

        # Add if we don't already know of this instantiation
        instantiation = templ.arguments[0...arg_count].map do |arg|
          @db.resolve_aliases(arg).full_name
        end

        container.instantiations << instantiation
      end

      # Returns the count of template arguments expected for a container of
      # *type*.
      private def container_type_arguments(type)
        case type
        when .sequential?  then 1
        when .associative? then 2
        else
          raise "BUG: Missing case for #{type.inspect}"
        end
      end
    end
  end
end
