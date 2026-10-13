require "spec"
require "../src/bindgen/library"

# ## Helpers

# Short-hand functions
module Parser
  include Bindgen::Parser

  def self.void_type
    Bindgen::Parser::Type::VOID
  end

  def self.type(cpp_type : String) : Bindgen::Parser::Type
    Bindgen::Parser::Type.parse(cpp_type)
  end

  def self.argument(name : String, cpp_type : String, default = nil, has_default = false) : Bindgen::Parser::Argument
    has_default ||= default != nil # Does it actually have a default?
    Bindgen::Parser::Argument.new(
      name: name,
      type: type(cpp_type),
      has_default: has_default,
      value: default,
    )
  end

  def self.method(name : String, class_name : String, result : Bindgen::Parser::Type, arguments : Array(Bindgen::Parser::Argument), type = Bindgen::Parser::Method::Type::MemberMethod)
    args = arguments.map do |arg|
      if arg.is_a?(Tuple)
        Parser.argument(*arg)
      else
        arg
      end
    end

    ret = result.is_a?(String) ? Parser.type(result) : result

    Bindgen::Parser::Method.new(
      type: type,
      access: Bindgen::Parser::AccessSpecifier::Public,
      name: name,
      class_name: class_name,
      arguments: args,
      return_type: ret,
      first_default_argument: args.index(&.has_default?),
    )
  end

  def self.method(name : String, class_name : String, result : Bindgen::Parser::Type, type = Bindgen::Parser::Method::Type::MemberMethod)
    method(name, class_name, result, [] of Bindgen::Parser::Argument, type)
  end
end
