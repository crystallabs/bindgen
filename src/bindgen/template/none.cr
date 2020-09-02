module Bindgen
  module Template
    # The no-op template that returns *code* unmodified.
    class None < Base
      def no_op? : Bool
        true
      end

      def template(code) : String
        code
      end

      def ==(_other : self)
        true
      end
    end
  end
end
