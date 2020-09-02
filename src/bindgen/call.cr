module Bindgen
  # Stores a representation of a method call, or a method definition.
  # These are nuilt by language-specific processors, and are written by the
  # generators.
  #
  # A `Call` is generally platform-specific: They are bound to a certain context
  # which is described by the code around it.
  #
  # Think about a call like a piece of code that has no side-effects on its
  # surroundings:  Its body is self-contained, which expects variables as given
  # in the *arguments* list, and returns something described by the *result*.
  class Call
    # Base-class for `Result` and `Argument`.
    abstract class Expression
      # The data this expression originated in.
      getter type : Parser::Type

      # Pass in as reference?
      getter reference : Bool

      # Pointer depth, *without* the reference "pointer"
      getter pointer : Int32

      # Type to use for passing
      getter type_name : String

      # Is this expression nil-able?  A type is only nil-able if the wrapped
      # type is an object-type (`Reference` in Crystal), and the C++-world
      # accepts this pointer being `nullptr`.
      getter? nilable : Bool

      def initialize(@type, @reference, @pointer, @type_name, @nilable)
      end

      def_equals_and_hash @type, @reference, @pointer, @type_name, @nilable
    end

    # Call result type configuration.
    class Result < Expression
      # Conversion template to get the data out of the method, ready to be
      # returned back.
      getter conversion : Template::Base

      def initialize(@type, @type_name, @reference, @pointer, @conversion = Template::None.new, @nilable = false)
      end

      # Applies the result's conversion template to a piece of code.
      def apply_conversion(code : String) : String
        conversion.template(code)
      end

      # Converts the result into an argument of *name*.
      def to_argument(name : String, default = nil) : Argument
        call = apply_conversion(name)

        Argument.new(
          type: @type,
          type_name: @type_name,
          name: name,
          call: call,
          reference: @reference,
          pointer: @pointer,
          nilable: @nilable,
          default_value: default,
        )
      end
    end

    # A result specifying a `Proc`.
    class ProcResult < Result
      # Converts the result into an argument of *name*.
      def to_argument(name : String, block = false) : Argument
        call = apply_conversion(name)

        ProcArgument.new(
          block: block,
          type: @type,
          type_name: @type_name,
          name: name,
          call: call,
          reference: @reference,
          pointer: @pointer,
          nilable: @nilable,
        )
      end
    end

    # A `Call` argument.
    class Argument < Expression
      # The variable name.
      getter name : String

      # How to use the argument variable.
      getter call : String

      # Default value for this argument.
      getter default_value : Parser::DefaultValueTypes?

      def initialize(@type, @type_name, @name, @call, @reference = false,
                     @pointer = 0, @default_value = nil, @nilable = false)
      end
    end

    # An argument specifying a var-arg (`...`) argument.
    # Also see `TypeHelper#variadic_argument`.
    class VariadicArgument < Argument
    end

    # A type argument whose type is a metaclass (`T.class`).
    # Only used for Crystal code to disambiguate block overloads.
    class TypeArgument < Argument
    end

    # A `Proc` argument.  May be a block.
    class ProcArgument < Argument
      # Is this a block argument?
      getter? block : Bool

      def initialize(@type, @type_name, @name, @call, @reference = false,
                     @pointer = 0, @default_value = nil, @nilable = false, @block = false)
      end
    end

    # The body of a `Call` which is to be materialized as function or method of
    # some sort.  The `Generator` will later call `#to_code` with its *platform*
    # to generate the code, which it will then embed into the function itself.
    #
    # ## Choosing a body type
    #
    # When building a custom `Body`, consider using `HookableBody` instead to
    # allow later processors to augment your body.
    abstract class Body
      # Will be called by a `Generator` later on, passing in the *call* and the
      # target *platform*.
      abstract def to_code(call : Call, platform : Graph::Platform) : String
    end

    # A body allowing to add additional code before and after the actual code
    # body.  This is useful to allow later processors to refine existing calls
    # with additional logic.  An example of this is the `VirtualOverride`
    # processor, which uses this to augment `#initialize` methods setting the
    # jump-table.
    #
    # **Note**: The *pre_hook* and *post_hook* must be manually called in your
    # `#to_code` implementation.
    #
    # See `CallBuilder::CrystalBinding::InvokeBody` for an example of this.
    abstract class HookableBody < Body
      # Code snippet ran before the body code itself.  Access to the arguments
      # of the body can be accessed directly by their name.
      property pre_hook : Body?

      # Code snippet ran after the body code itself.  The result value is stored
      # in a variable called `result`.
      property post_hook : Body?
    end

    # Dummy body, storing a fixed empty body.
    class EmptyBody < Body
      def to_code(_call : Call, _platform : Graph::Platform) : String
        ""
      end
    end

    # Origin method
    getter origin : Parser::Method

    # Full name of the method call, e.g. `new Foo` or `_self_->doIt`.
    getter name : String

    # Arguments
    getter arguments : Array(Argument)

    # Return type
    getter result : Result

    # The call body, semi-serialized.
    getter body : Body

    def initialize(@origin, @name, @result, @arguments, @body)
    end
  end
end
