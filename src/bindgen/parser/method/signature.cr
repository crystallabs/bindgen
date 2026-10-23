module Bindgen
  module Parser
    class Method
      # Parses a C++ member method declaration, as written in a header, into a
      # `Method` of the class *class_name*, for the `declare_methods:` type
      # rule: `QMenu *menu() const`, `static Foo *make(int count = 1)`,
      # `void setMenu(QMenu *menu)`.  Every argument is named, like in a
      # declaration.  A default is exposed if it's a literal number, boolean
      # or `nullptr`.  Raises an `ArgumentError` for anything else.
      def self.from_signature(signature : String, class_name : String) : Method
        SignatureParser.new(signature, class_name).parse
      end

      # Parser of `.from_signature`, see there.
      private struct SignatureParser
        # The identifier a declarator ends in: the name of the method or
        # argument.
        NAME_RX = /\s*([A-Za-z_][A-Za-z0-9_]*)$/

        # The defaults the parser exposes to Crystal, see `Argument#value`.
        INTEGER_RX = /^[+-]?\d+$/
        FLOAT_RX   = /^[+-]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?$/

        def initialize(@signature : String, @class_name : String)
        end

        def parse : Method
          source = @signature.strip
          const = false
          static = false

          if source.ends_with?("const")
            const = true
            source = source.rchop("const").rstrip
          end

          if source.starts_with?("static ")
            static = true
            source = source.lchop("static ").lstrip
          end

          head, found, tail = source.partition('(')
          fail "no argument list" if found.empty?
          fail "no closing parenthesis" unless tail.ends_with?(')')
          return_type, name = split_declarator(head)
          fail "no method name" if name.nil? || return_type.empty?

          arguments = split_arguments(tail.rchop(')')).map_with_index do |arg, idx|
            parse_argument(arg, idx)
          end

          Method.new(
            type: static ? Method::Type::StaticMethod : Method::Type::MemberMethod,
            access: AccessSpecifier::Public,
            name: name,
            class_name: @class_name,
            arguments: arguments,
            first_default_argument: arguments.index(&.has_default?),
            return_type: Parser::Type.parse(return_type),
            const: const,
          )
        end

        # Splits a declarator like `const QMenu *menu` into the type and the
        # trailing name, if any: `{"const QMenu *", "menu"}`.
        private def split_declarator(declarator : String) : {String, String?}
          declarator = declarator.strip
          if match = declarator.match(NAME_RX)
            type = match.pre_match.strip
            return {type, match[1]} unless type.empty? || type.ends_with?("::")
          end

          {declarator, nil}
        end

        # Splits the *list* of arguments at the commas outside of template
        # argument lists and parentheses.
        private def split_arguments(list : String) : Array(String)
          arguments = [] of String
          depth = 0
          current = String::Builder.new

          list.each_char do |char|
            case char
            when '<', '(' then depth += 1
            when '>', ')' then depth -= 1
            end

            if char == ',' && depth == 0
              arguments << current.to_s
              current = String::Builder.new
            else
              current << char
            end
          end

          arguments << current.to_s
          arguments.reject(&.blank?)
        end

        # Parses the argument *source*, like `int count = 1`, at *index*.
        private def parse_argument(source : String, index : Int32) : Argument
          declarator, _, default = source.partition('=')
          type, name = split_declarator(declarator)
          fail "argument #{index + 1} needs a name" if name.nil?

          has_default = !default.strip.empty?
          Argument.new(
            name: name,
            type: Parser::Type.parse(type),
            has_default: has_default,
            value: has_default ? default_value(default.strip) : nil,
          )
        end

        # The default *literal* as the clang tool reports it, or `nil` for an
        # expression Crystal can't take.
        private def default_value(literal : String) : DefaultValueTypes?
          case literal
          when "true"     then true
          when "false"    then false
          when "nullptr"  then true # A null pointer, see `Argument#defaults_to_nil?`
          when INTEGER_RX then literal.to_i64
          when FLOAT_RX   then literal.to_f64
          end
        end

        private def fail(reason : String)
          raise ArgumentError.new("declare_methods of #{@class_name}: can't parse #{@signature.inspect}: #{reason}")
        end
      end
    end
  end
end
