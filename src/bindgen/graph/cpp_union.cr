module Bindgen
  module Graph
    # A `lib union` in Crystal, or a plain `union` in C/C++.
    class CppUnion < Container
      # Variant members in this structure.
      getter fields : Hash(String, Call::Result)

      # Bit-fields of a `lib union`, which get getter and setter methods.
      getter bit_fields = [] of Struct::BitField

      def initialize(@fields, name, parent)
        super(name, parent)
      end
    end
  end
end
