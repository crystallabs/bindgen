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

      # Name of the base-class, if any.  This is mainly useful for C++ to
      # generate the jump-table.
      property base_class : String?

      def initialize(@fields, name, parent, @base_class = nil)
        super(name, parent)
      end
    end
  end
end
