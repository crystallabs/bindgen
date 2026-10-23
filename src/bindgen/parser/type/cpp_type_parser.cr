require "string_scanner"

module Bindgen
  module Parser
    class Type
      # Parser for qualified C++ type-names.  It's really stupid though.
      private class CppTypeParser
        # Regex that matches the opening of a template argument list.
        OPEN_RX = /</

        # Regex that matches the closing of a template argument list, including
        # an optional suffix that forms part of the preceding template type.
        CLOSE_RX = />([^,>]*)/

        # Regex matching everything that does not delimit a template argument
        # list.
        NEITHER_RX = /[^<>]+/

        # The fundamental types of C++, which the clang tool reports as
        # built-in: `unsigned long int`, `char16_t`, `long double`.
        FUNDAMENTAL_RX = /^(?:(?:(?:signed|unsigned)\s+)?(?:char|short(?:\s+int)?|int|long(?:\s+int)?|long\s+long(?:\s+int)?)|signed|unsigned|bool|void|float|double|long\s+double|wchar_t|char8_t|char16_t|char32_t)$/

        def parse(type_name : String, pointer_depth : Int32 = 0)
          parse_type(type_name, pointer_depth)
        end

        # Parses a C++ type.  Recursively parses all templates contained within,
        # unless a template instantiation is explicitly given.
        private def parse_type(type_name, pointer_depth, template = nil) : Type
          name = type_name.strip # Clean the name
          reference = false
          const = false
          pointer = 0

          # Is it const-qualified?
          if name.starts_with?("const ")
            const = true
            name = name[6..-1] # Remove `const `
          end

          name, array_indirections = split_array_indirections(name)

          # Is it a reference?
          if name.ends_with?('&')
            reference = true
            pointer_depth += 1
            name = name[0..-2] # Remove ampersand
          end

          # Is it a C array?
          extents = [] of UInt64
          while subscript = name.match(/\s*\[\s*(\d*)\s*\]\s*$/)
            extents.unshift subscript[1].to_u64 { 0_u64 }
            pointer_depth += 1
            name = subscript.pre_match
          end

          # Is it a pointer?
          while name.ends_with?('*')
            pointer += 1
            pointer_depth += 1
            name = name[0..-2] # Remove star
          end

          name = name.strip

          # The indirections of a pointer or reference to a C array come last.
          array_pointer = 0
          if array_indirections && !extents.empty?
            array_pointer = array_indirections.size
            reference = array_indirections.ends_with?('&')
            pointer_depth += array_pointer
            pointer += array_pointer
            pointer -= 1 if reference
          end

          # Is it a template?
          if template
            # Adjust template name to remove `const` etc.
            template = Template.new(
              base_name: name.match(OPEN_RX).try(&.pre_match) || name,
              full_name: name,
              arguments: template.arguments,
            )
          elsif name =~ OPEN_RX || name =~ CLOSE_RX
            template = parse_template(name.strip)
          end

          typer = Cpp::Typename.new

          # Build the `Type`
          Type.new(
            const: const,
            move: false,
            reference: reference,
            builtin: FUNDAMENTAL_RX.matches?(name),
            void: (name == "void"),
            pointer: pointer_depth,
            extents: extents,
            array_pointer: array_pointer,
            base_name: name,
            full_name: typer.full(name, const, pointer, reference, extents, array_pointer),
            template: template,
            nilable: false,
          )
        end

        # Splits the indirections off a pointer or reference to a C array.  Both
        # `int (*)[4]` and `int [4] *` return `{"int [4]", "*"}`.
        private def split_array_indirections(name) : {String, String?}
          if match = name.match(/\(\s*([*&\s]+)\)\s*((?:\[\s*\d*\s*\]\s*)+)$/)
            {"#{match.pre_match} #{match[2]}", match[1].delete(' ')}
          elsif match = name.match(/\]\s*([*&\s]+)$/)
            {name[0..match.begin(0)], match[1].delete(' ')} # Keep the bracket
          else
            {name, nil}
          end
        end

        # Tree structure of a template.
        alias TemplateTree = Type | Array(TemplateTree)

        # this won't work for some reason
        # alias TemplateTree = Array(Type | TemplateTree)

        # Parses a C++ template.  Recursively parses all types within.
        # *type_name* is expected to be a plain type (without `const`, pointers,
        # or references).
        private def parse_template(type_name) : Template?
          typer = Cpp::Typename.new
          scanner = StringScanner.new(type_name)
          top = [] of TemplateTree
          stack = [top]

          until scanner.eos?
            if scanner.scan(OPEN_RX)
              top = [] of TemplateTree
              stack << top
            elsif scanner.scan(CLOSE_RX)
              template_args = stack.pop.map(&.as(Type))

              raise "Extra closing bracket" if stack.empty?
              top = stack.last
              template_type = top.pop?
              raise "Template argument list without template name" unless template_type.is_a?(Type)

              suffix = scanner[1]
              arg_list = template_args.map(&.full_name)
              base_name = template_type.full_name
              full_name = "#{typer.template_class base_name, arg_list}#{suffix}".strip
              template = Template.new(
                base_name: base_name,
                full_name: full_name,
                arguments: template_args,
              )

              type = parse_type(full_name, 0, template)
              top << type
            elsif text = scanner.scan(NEITHER_RX)
              parts = text.split(',', remove_empty: true)
              types = parts.compact_map do |part|
                parse_type(part.strip, 0) unless part.blank?
              end
              top.concat(types)
            end
          end

          raise "Extra opening bracket" unless stack.size == 1
          raise "Multiple top-level types" unless top.size == 1

          top.first.as(Type).template
        end
      end
    end
  end
end
