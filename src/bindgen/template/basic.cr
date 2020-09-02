module Bindgen
  module Template
    # The default template.  Uses `Util.template` to substitute *code* into the
    # given *pattern*.
    #
    # If *simple* is given, the template will only use a subset of the features;
    # `%` performs substitution, whereas the escape sequence `%%` outputs a
    # literal percent sign.
    class Basic < Base
      def initialize(@pattern : String, @simple = false)
      end

      def no_op? : Bool
        @pattern == "%"
      end

      def template(code) : String
        if @simple
          @pattern.gsub(/%+/) do |m|
            literals = "%" * (m.size // 2)
            out_code = code if m.size % 2 == 1
            "#{literals}#{out_code}"
          end
        else
          Util.template(@pattern, code)
        end
      end

      def_equals @pattern, @simple
    end
  end
end
