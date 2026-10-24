module Bindgen
  module Graph
    # A `struct` in Crystal (`lib` or not), or a plain `struct` in C++.
    #
    # A structure can host both raw non-static variable fields (C-style) and
    # other methods at once.
    class Struct < Container
      # Used to signal the `Generator::Cpp` to generate a `using BASE::BASE;`.
      INHERIT_CONSTRUCTORS_TAG = "INHERIT_CONSTRUCTORS_TAG"

      # Used to signal the `Generator::Cpp` to generate a constructor copying
      # an instance of the base class, which isn't inherited by the above.
      COPY_BASE_CONSTRUCTOR_TAG = "COPY_BASE_CONSTRUCTOR_TAG"

      # Non-static fields in this structure.
      getter fields : Hash(String, Call::Result)

      # Default member initializers of `fields`, by name, as C++ expressions:
      # `nullptr`.  Only `Generator::Cpp` writes them.
      getter field_defaults = {} of String => String

      # Name of the base-class, if any.  This is mainly useful for C++ to
      # generate the jump-table.
      property base_class : String?

      # Bit-fields of a `lib struct`, which get getter and setter methods.
      getter bit_fields = [] of BitField

      # Are the fields packed without alignment, as in a `@[Packed]` struct?
      getter? packed : Bool

      # A bit-field of a `lib struct` or `lib union`.  It is stored in the integer member
      # *storage* of type *storage_type*, which is *unit_bits* wide, at the bit
      # *shift* counted from its least significant bit.  A signed bit-field has
      # the signed counterpart of the storage type as *signed_type*.
      #
      # The *getter_fun* and *setter_fun* are the `lib` functions accessing it
      # through C++.  Without them, the methods shift and mask *storage*
      # instead.
      record BitField,
        name : String,
        type_name : String,
        storage : String,
        storage_type : String,
        unit_bits : Int64,
        shift : Int64,
        width : Int32,
        signed_type : String?,
        bool : Bool,
        const : Bool,
        doc : String?,
        getter_fun : String? = nil,
        setter_fun : String? = nil

      def initialize(@fields, name, parent, @base_class = nil, @packed = false)
        super(name, parent)
      end
    end
  end
end
