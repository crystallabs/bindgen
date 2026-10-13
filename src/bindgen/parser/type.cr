require "./type/cpp_type_parser"

module Bindgen
  module Parser
    # Stores information about a specific C++ type.
    class Type
      include JSON::Serializable

      # Name of the `CrystalProc` C++ and Crystal type.  This type is a template
      # type in C++, and a `struct` in Crystal.
      CRYSTAL_PROC = "CrystalProc"

      # Type kinds.  Currently not used by the clang tool.
      # TODO: use `Parser::TypeKind` instead
      enum Kind
        Class
        Struct
        Enum
        Function # `CrystalProc`; template type in C++, non-generic in Crystal
      end

      # ATTENTION: Make sure to update other methods in here, in `Argument` and
      # in `Field` as required!

      # Type kind.
      getter kind = Bindgen::Parser::Type::Kind::Class

      # Is this type constant?
      @[JSON::Field(key: "isConst")]
      getter? const : Bool

      # Is this a C++ rvalue reference type?
      @[JSON::Field(key: "isMove")]
      getter? move : Bool

      # Is this a C++ lvalue reference type?
      @[JSON::Field(key: "isReference")]
      getter? reference : Bool

      # Is this type a C++ built-in type?
      @[JSON::Field(key: "isBuiltin")]
      getter? builtin : Bool

      # Is it C++ `void`?  Note that `void *` is also void.
      # See also `#pure_void?`
      @[JSON::Field(key: "isVoid")]
      getter? void : Bool

      # Total number of indirections from pointers, lvalue references and C
      # array extents.
      getter pointer : Int32

      # C array extents, outermost first.  E.g. `int [][5][3]` has the extents
      # `[0, 5, 3]`.
      @extents = Array(UInt64).new

      # Unqualified base name for easier mapping to Crystal.
      #
      # E.g., the base name of `const QWidget *&` is `QWidget`.
      @[JSON::Field(key: "baseName")]
      getter base_name : String

      # Fully qualified, full name, for the C++ bindings.
      @[JSON::Field(key: "fullName")]
      getter full_name : String

      # Is this type nilable?  For compatibility with `Argument`.
      @[JSON::Field(key: "acceptsNull")]
      getter? nilable = false

      # Template information, if this type is a template type.
      getter template : Template?

      # `Void` type
      VOID = new(
        const: false,
        move: false,
        reference: false,
        builtin: true,
        void: true,
        pointer: 0,
        base_name: "void",
        full_name: "void",
        template: nil,
        nilable: false,
      )

      # Empty type, as is returned by the parser for constructors.  Only valid
      # as a return type of a constructor method.
      EMPTY = new(
        const: false,
        move: false,
        reference: false,
        builtin: true,
        void: false,
        pointer: 0,
        base_name: "",
        full_name: "",
        template: nil,
        nilable: false,
      )

      # Returns a `Type` of a C++ built-in type *cpp_name*.
      def self.builtin_type(cpp_name : String, pointer = 0, reference = false)
        new(
          const: false,
          move: false,
          reference: reference,
          builtin: true,
          void: (cpp_name == "void"),
          pointer: pointer,
          base_name: cpp_name,
          full_name: cpp_name,
          template: nil,
          nilable: false,
        )
      end

      # Returns a `Type` of a fully qualified C++ typename *type_name*.  Extra
      # pointer indirections can be set by *pointer_depth*.
      def self.parse(type_name : String, pointer_depth = 0)
        CppTypeParser.new.parse(type_name, pointer_depth)
      end

      # Creates a `Type` describing a Crystal `Proc` type, which returns a
      # *return_type* using *arguments*.
      #
      # The generated type will be considered a built-in type.
      def self.proc(return_type : Type, arguments : Enumerable(Type))
        base = CRYSTAL_PROC

        template_args = [return_type] + arguments.to_a
        template = Template.new(
          full_name: base,
          base_name: base,
          arguments: template_args,
        )

        typer = Cpp::Typename.new
        specialization = typer.template_class(base, template_args.map(&.full_name))
        # Build the `Type`
        new(
          kind: Kind::Function,
          const: false,
          move: false,
          reference: false,
          builtin: true,
          void: false,
          pointer: 0,
          base_name: specialization,
          full_name: specialization,
          template: template,
          nilable: false,
        )
      end

      # Decays the type.  This means that a single "layer" of information is
      # removed from this type.  Each rule is tried in the following order.
      # The first winning rule returns a new type.
      #
      # 1. If `#c_array?`, remove outermost extent (`int [4][3]` -> `int [3]`)
      # 2. If `#const?`, remove const (`const int &` -> `int &`)
      # 3. If `#reference?`, pointer-ize (`int &` -> `int *`)
      # 4. If `#pointer > 0`, remove one (`int *` -> `int`)
      # 5. Else, it's the base-type already.  Return `nil`.
      def decayed : Type?
        is_const = @const
        is_ref = @reference
        ptr = @pointer
        extents = @extents

        if extents.size > 0 # 1.
          extents = extents[1..]
          ptr -= 1
        elsif is_const # 2.
          is_const = false
        elsif is_ref # 3.
          is_ref = false
        elsif ptr > 0 # 4.
          ptr -= 1
        else # 5.
          return nil
        end

        typer = Cpp::Typename.new
        type_ptr = ptr - extents.size
        type_ptr -= 1 if is_ref

        Type.new(
          kind: @kind,
          const: is_const,
          reference: is_ref,
          move: false,
          builtin: @builtin,
          void: @void,
          pointer: ptr,
          extents: extents,
          base_name: @base_name,
          full_name: typer.full(@base_name, is_const, type_ptr, is_ref, extents),
          template: @template,
          nilable: @nilable,
        )
      end

      # If the type is a pointer and not a reference, returns a copy of this
      # type that is nilable, otherwise returns `nil`.
      def make_pointer_nilable : Type?
        if @pointer > 0 && !@reference && !@move
          Type.new(
            kind: @kind,
            const: @const,
            reference: false,
            move: false,
            builtin: @builtin,
            void: @void,
            pointer: @pointer,
            extents: extents,
            base_name: @base_name,
            full_name: @full_name,
            template: @template,
            nilable: true,
          )
        end
      end

      # Checks whether this type uses *name* in its base name or any of its
      # template arguments.  Does not check for template names.
      def uses_typename?(name : String)
        if template = @template
          template.arguments.any?(&.uses_typename?(name))
        else
          @base_name == name
        end
      end

      # Performs type substitution with the given *replacements*.
      #
      # Substitution is performed if this type's base name is exactly one of the
      # type arguments, but not if the type is a templated type of the same
      # name.  Substitution is applied recursively on template type arguments.
      # All substitutions are applied simultaneously.
      def substitute(replacements : Hash(String, Type)) : Type
        if template = @template
          substitute_template(replacements, template)
        elsif type = replacements[@base_name]?
          substitute_base(type)
        else
          self
        end
      end

      # Substitutes all uses of *name* with the given *type*.
      def substitute(name : String, with type : Type) : Type
        substitute({name, type})
      end

      # :ditto:
      def substitute(replacements : Tuple(String, Type)) : Type
        if template = @template
          substitute_template(replacements, template)
        elsif @base_name == replacements[0]
          substitute_base(replacements[1])
        else
          self
        end
      end

      # Helper for `#substitute`.  Performs type substitution on the type's
      # template arguments.
      private def substitute_template(replacements, template) : Type
        typer = Cpp::Typename.new
        template_args = template.arguments.map(&.substitute(replacements))
        template_base = template.base_name
        template_full = typer.template_class(template_base, template_args.map(&.full_name))

        subst_template = Template.new(
          base_name: template_base,
          full_name: template_full,
          arguments: template_args,
        )

        typer = Cpp::Typename.new
        type_ptr = @pointer - @extents.size - (reference? ? 1 : 0)

        Type.new(
          kind: @kind,
          const: @const,
          reference: @reference,
          move: @move,
          builtin: @builtin,
          void: @void,
          pointer: @pointer,
          extents: extents,
          base_name: template_full,
          full_name: typer.full(template_full, @const, type_ptr, @reference, @extents),
          template: subst_template,
          nilable: @nilable,
        )
      end

      # Helper for `#substitute`.  Performs basic type substitution on this
      # type.  Const-ness, references, and pointers are propagated.
      private def substitute_base(type)
        const = type.const? || const?
        reference = type.reference? || reference?
        move = !reference && (type.move? || move?)
        pointer = @pointer + type.pointer - (type.reference? && reference? ? 1 : 0)

        if @pointer > 0 && !reference? && type.reference?
          reference = false
          pointer -= 1
        end

        typer = Cpp::Typename.new
        type_ptr = pointer - @extents.size - (reference ? 1 : 0)

        Type.new(
          kind: type.kind,
          const: const,
          reference: reference,
          move: move,
          builtin: type.builtin?,
          void: type.void?,
          pointer: pointer,
          extents: extents,
          base_name: type.base_name,
          full_name: typer.full(type.base_name, const, type_ptr, reference, @extents),
          template: type.template,
          nilable: type.nilable?,
        )
      end

      def_equals_and_hash @base_name, @full_name, @const, @reference, @move,
        @builtin, @void, @pointer, @kind, @nilable, @template, @extents

      def initialize(
        @base_name, @full_name, @const, @reference, @pointer, @move = false,
        @builtin = false, @void = false, @kind = Kind::Class, @template = nil,
        @nilable = false, @extents = Array(UInt64).new
      )
      end

      # Checks if this type equals the *other* type, except for nil-ability.
      def equals_except_nil?(other : Type)
        {% for i in %i[base_name full_name const reference move builtin void pointer kind template extents] %}
          return false if @{{ i.id }} != other.@{{ i.id }}
        {% end %}

        true
      end

      # Returns `true` if this type is `void`, and nothing else.
      def pure_void?
        @void && @pointer == 0
      end

      # The array extents of this type.
      def extents
        @extents.dup
      end

      # Is this type a C array?
      def c_array?
        @extents.size > 0
      end

      # Is this type a C array with known size?
      def c_complete_array?
        c_array? && @extents.none?(&.zero?)
      end

      # Returns a copy of this type with C array extents removed.
      def remove_all_extents : Type
        ptr = @pointer - @extents.size
        extents = Array(UInt64).new

        typer = Cpp::Typename.new
        type_ptr = ptr
        type_ptr -= 1 if @reference

        Type.new(
          kind: @kind,
          const: @const,
          reference: @reference,
          move: false,
          builtin: @builtin,
          void: @void,
          pointer: ptr,
          extents: extents,
          base_name: @base_name,
          full_name: typer.full(@base_name, @const, type_ptr, @reference, extents),
          template: @template,
          nilable: @nilable,
        )
      end

      # The mangled type name for C++ bindings.
      def mangled_name
        Util.mangle_type_name @full_name
      end
    end
  end
end
