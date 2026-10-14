module Bindgen
  module Template
    # Wraps a template that uses `%` more than once, so that the code, commonly
    # a function call, is evaluated only once.  The code is bound to a variable
    # named `bg_value`, which the *pattern* then uses instead.
    class EvaluateOnce < Base
      # Name of the variable the code is bound to.
      VARIABLE = "bg_value"

      enum Language
        Cpp
        Crystal
      end

      def initialize(@pattern : Basic, @language : Language)
      end

      def no_op? : Bool
        false
      end

      def template(code) : String
        body = @pattern.template(VARIABLE)

        case @language
        in .cpp?
          "([&]() { auto &&#{VARIABLE} = (#{code}); return #{body}; }())"
        in .crystal?
          "BindgenHelper.evaluate_once(#{code}) { |#{VARIABLE}| #{body} }"
        end
      end

      def_equals @pattern, @language
    end
  end
end
