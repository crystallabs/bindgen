module Bindgen
  module Parser
    # Describes a C++ `class`, `struct`, or `union`.
    class Class
      include JSON::Serializable

      # Collection of classes.
      alias Collection = Hash(String, Class)

      # Visibility of the class.  Default is public, but some generated Crystal
      # classes may be private.
      getter access = Bindgen::Parser::AccessSpecifier::Public

      # The keyword used to declare this type (`class`, `struct`, or `union`).
      @[JSON::Field(key: "typeKind")]
      getter type_kind : TypeKind

      # Does the type have a default, argument-less constructor?
      @[JSON::Field(key: "hasDefaultConstructor")]
      getter? has_default_constructor : Bool

      # Is the type copy-constructible?
      @[JSON::Field(key: "hasCopyConstructor")]
      getter? has_copy_constructor : Bool

      # Is this class abstract?
      @[JSON::Field(key: "isAbstract")]
      getter? abstract : Bool

      # Is this class anonymous?
      @[JSON::Field(key: "isAnonymous")]
      getter? anonymous : Bool

      # Is this class publicly destructible?
      @[JSON::Field(key: "isDestructible")]
      getter? destructible : Bool

      # Fully qualified name of the class.
      getter name : String

      # Size of an instance of the class in memory.
      @[JSON::Field(key: "byteSize")]
      getter byte_size : Int32

      # Direct bases of the class.
      getter bases : Array(BaseClass)

      # Data members defined in the class, both static and non-static.
      getter fields : Array(Field)

      # Methods defined in the class.
      getter methods : Array(Method)

      def initialize(
        @name, @byte_size = 0, @has_default_constructor = false,
        @has_copy_constructor = false, @type_kind = TypeKind::Class,
        @abstract = false, @anonymous = false, @destructible = true,
        @bases = [] of BaseClass, @fields = [] of Field,
        @methods = [] of Method, @access = AccessSpecifier::Public,
      )
      end

      delegate public?, protected?, private?, to: @access

      # Is this a `class`, `struct`, or C `union`?
      delegate class?, struct?, cpp_union?, to: @type_kind

      # Does this class have any virtual methods?
      def has_virtual_methods?
        @methods.any?(&.virtual?)
      end

      # The full binding function name of the destructor.
      def destructor_name : String
        "bg_#{binding_name}_DESTROY"
      end

      # The name of the class as part of binding methods.
      def binding_name : String
        Util.mangle_type_name(@name)
      end

      # Constructs a method destroying an instance of this class.
      def destructor_method : Method
        Parser::Method.new(
          type: Method::Type::Destructor,
          name: "DESTROY",
          access: AccessSpecifier::Public,
          const: false,
          virtual: true, # Hopefully.
          pure: false,
          class_name: @name,
          arguments: [] of Argument,
          first_default_argument: nil,
          return_type: Type::VOID,
        )
      end

      # List of all wrappable-methods.  This includes all `Method#variants`.
      # Methods which use `Method#move_semantics?` on any type are explicitly
      # removed.
      #
      # Note: This is a memoized getter.  Thus it's cheap to call it multiple
      # times.
      getter wrap_methods : Array(Method) do
        list = [] of Method

        # Collect all method variants
        each_wrappable_method do |method|
          method.variants { |m| list << m }
        end

        # And make sure there are no duplicates.
        Util.uniq_by(list) { |a, b| a.equals_except_const?(b) || a.equals_virtually?(b) }
      end

      # Yields each wrappable method without any further processing.
      #
      # **Note**: This method hard-codes which methods to ignore.  If you're
      # wondering why a method doesn't even reach the graph in the first place,
      # look in here.
      def each_wrappable_method(&)
        @methods.each do |method|
          next if method.private?
          next if method.name == "operator="  # TODO: Support assignments!
          next if method.conversion_operator? # TODO: Support conversions!
          next if method.copy_constructor?    # TODO: Support copy constructors!
          next if method.has_move_semantics?  # Move semantics are hard to wrap.

          # Don't try to wrap copy-constructors in an abstract class.
          next if abstract? && method.copy_constructor?

          yield method
        end
      end

      # Non-yielding version of `#each_wrappable_method`
      def wrappable_methods
        list = [] of Method
        each_wrappable_method { |m| list << m }
        list
      end

      # Assumes that *method* exists in a class inheriting from this class.
      # Tries to find a method in this class which is overriden by *method*.
      def find_parent_method(method : Method) : Method?
        @methods.find do |m|
          next if method.arguments.size != m.arguments.size
          next if method.name != m.name # Name check
          next unless method.return_type.equals_except_nil?(m.return_type)

          # Check all arguments for type-equality.
          hit_count = 0
          method.arguments.zip(m.arguments) do |l, r|
            break unless l.type_equals?(r)
            hit_count += 1
          end

          hit_count == method.arguments.size
        end
      end

      # Returns a `Type` referencing this class.
      def as_type(pointer = 1, reference = false, const = false) : Type
        typer = Cpp::Typename.new

        kind = case type_kind
               when .struct? then Type::Kind::Struct
               when .enum?   then Type::Kind::Enum
               else               Type::Kind::Class
               end

        Type.new(
          kind: kind,
          const: const,
          reference: reference,
          move: false,
          void: false,
          builtin: false,
          base_name: name,
          full_name: typer.full(name, const, pointer, reference),
          pointer: pointer + (reference ? 1 : 0),
        )
      end
    end
  end
end
