module Bindgen
  module Template
    # Compound template which runs *code* through multiple child templates, in
    # the order they are given in the constructor.
    class Sequence < Base
      getter children = Array(Base).new
      getter? no_op : Bool = true

      def initialize(*conversions : Base)
        conversions.each do |conversion|
          # Flatten `Sequence` templates automatically.
          if conversion.is_a?(Sequence)
            @children.concat(conversion.children)
          else
            @children << conversion
          end

          # `Sequence` templates returned by `#followed_by` are by construction
          # never no-op, but we'll compute this in case `Sequence` is manually
          # created.
          @no_op &&= conversion.no_op?
        end
      end

      def template(code) : String
        @children.each do |conversion|
          code = conversion.template(code)
        end

        code
      end

      def_equals @children
    end
  end
end
