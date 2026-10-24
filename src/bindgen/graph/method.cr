module Bindgen
  module Graph
    # A method, and its calls.  The `#calls` will be populated later on by
    # processors.
    class Method < Node
      # If this tag is set, it means this method is a `#initialize(unwrap: )`.
      # The value is left empty.
      UNWRAP_INITIALIZE_TAG = "UNWRAP_INITIALIZE_TAG"

      # If this tag is set, this method will bind directly to the method named
      # in the value.  `Processor::CppWrapper` won't generate a wrapper for this
      # method.  `Processor::CrystalBinding` will make the `fun` of this
      # function point to it.  The Crystal wrapper is not affected.
      EXPLICIT_BIND_TAG = "EXPLICIT_BIND_TAG"

      # If this tag is set, this method is expected to call a base class method
      # without dynamic lookup.  The value is left empty.
      SUPERCLASS_BIND_TAG = "SUPERCLASS_BIND_TAG"

      # If this tag is set, this methods CrystalBinding and Cpp calls can be
      # removed by a later processor.  The value is left empty.
      REMOVABLE_BINDING_TAG = "REMOVABLE_BINDING_TAG"

      # If this tag is set, the object of this method belongs to its argument at
      # the index in the value, like a Qt object to its parent: the Crystal
      # wrapper keeps the object alive while the argument isn't `nil`.  A
      # constructor keeps it alive if given one, another method keeps it alive
      # if given one, and releases it if given `nil`.  Set by `Processor::Qt`,
      # see `Processor::CrystalWrapper#add_owner_hook`.
      OWNED_BY_ARGUMENT_TAG = "OWNED_BY_ARGUMENT_TAG"

      # If this tag is set, C++ refers to the object of this method from then
      # on, like Qt to the sender of a connected signal: the Crystal wrapper
      # passes `self` to `BindgenHelper.keep_alive`.  The value is left empty.
      # Set by `Processor::Qt`, see `Processor::WrapperHooks#add_keeps_self_hook`.
      KEEPS_SELF_TAG = "KEEPS_SELF_TAG"

      # `Parser::Method` this method node is based on.
      getter origin : Parser::Method

      # Calls for the various `Generator`s
      getter calls = {} of Platform => Call

      def initialize(@origin, name, parent = nil)
        super(name, parent)
      end

      # Returns the class containing this method.
      def parent_class : Graph::Class?
        unspecific_parent.as?(Graph::Class)
      end

      # Returns a dot (`.`) if the origin method is static.  Returns a number
      # sign (`#`) otherwise.
      def crystal_prefix : String
        if @origin.static?
          "."
        else
          "#"
        end
      end

      # A method is not a constant in Crystal.
      def constant? : Bool
        false
      end

      def diagnostics_path : String
        args = @origin.arguments.map(&.name).join(", ")

        if @origin.name.empty?
          name = "initialize"
        end

        "#{super}#{name}(#{args})"
      end

      delegate mangled_name, to: @origin
    end
  end
end
