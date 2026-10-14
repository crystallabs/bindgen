module Bindgen
  module ConfigReader
    alias Version = Bindgen::FindPath::GenericVersion

    # Implements the condition evaluation logic of `Parser`.
    #
    # See `Parser`s documentation for a description of the syntax.
    #
    # You can sub-class this and pass an instance into a `Parser` if you want
    # to augment its feature-set.
    class ConditionEvaluator
      class Error < Exception
        getter condition_text : String

        def initialize(@condition_text, message)
          super(message)
        end
      end

      # Conditional types
      enum Verb
        If
        Elsif
        Else
      end

      # Regular expression for conditionals.
      # Matches: `[els]if VARIABLE (is|matches) VALUE`.
      # Instead of a space, an underscore may be used instead.
      RX = /^(?:els)?if(?: +|_)(.+?)(?: +|_)(is|isnt|matches|newer_or|older_or)(?: +|_)(.*)$/

      # Accessible variables
      getter variables : Hash(String, String)

      def initialize(@variables)
      end

      # Evaluates *condition_text*.
      def evaluate(condition_text : String, state : ConditionState) : {Bool, ConditionState}
        verb = read_verb(condition_text)
        case {state, verb}
        when {_, Verb::If}
          evaluate_condition(condition_text)
        when {ConditionState::AwaitingIf, Verb::Elsif}
          raise Error.new(condition_text, "elsif-branch without if-branch")
        when {ConditionState::Unmet, Verb::Elsif}
          evaluate_condition(condition_text)
        when {ConditionState::Met, Verb::Elsif}
          {false, state}
        when {ConditionState::AwaitingIf, Verb::Else}
          raise Error.new(condition_text, "else-branch without if-branch")
        when {ConditionState::Met, Verb::Else}
          {false, state}
        when {ConditionState::Unmet, Verb::Else}
          {true, ConditionState::Met}
        else # Illegal verb
          raise Error.new(condition_text, "Unknown condition verb")
        end
      end

      protected def evaluate_condition(condition_text : String)
        if run_condition(condition_text, *split(condition_text))
          {true, ConditionState::Met}
        else
          {false, ConditionState::Unmet}
        end
      end

      # Reads the conditional verb from *text*, if any.
      def read_verb(text : String) : Verb?
        if text.starts_with?("if") && delimiter_char?(text[2]?)
          Verb::If
        elsif text.starts_with?("elsif") && delimiter_char?(text[5]?)
          Verb::Elsif
        elsif text == "else"
          Verb::Else
        end
      end

      # Returns `true` if the *text* looks like a condition.  This is
      # used to feed all keys in a mapping into.
      def conditional?(text : String) : Bool
        read_verb(text) != nil
      end

      private def delimiter_char?(char)
        char == ' ' || char == '_'
      end

      # Runs the actual condition check.
      private def run_condition(text, variable, verb, test)
        value = get_value(variable)

        case verb
        when "is"       then value == test
        when "isnt"     then value != test
        when "matches"  then /#{test}/.match(value) != nil
        when "newer_or" then Version.parse(value) >= Version.parse(test)
        when "older_or" then Version.parse(value) <= Version.parse(test)
        else
          raise Error.new(text, "Unknown condition verb: #{verb} in #{text.inspect}")
        end
      end

      # Returns the value of *variable*.  If *variable* is not set, an empty
      # string is returned.
      protected def get_value(variable) : String
        @variables[variable]?.to_s
      end

      # Splits `foo_is_bar` into `{ "foo", "is", "bar" }`.  If matching failed,
      # raises.
      private def split(text : String)
        if m = RX.match(text)
          variable = m[1]
          verb = m[2]
          value = m[3]

          {variable, verb, value}
        else
          raise Error.new(text, "Malformed condition key: #{text.inspect}")
        end
      end
    end
  end
end
