require "../spec_helper"

class ClangValidationError < Exception
  getter document : JSON::Any::Type

  def initialize(@document, path, message)
    super("At #{path}: #{message}")
  end
end

# Runs the clang tool on *cpp_code*, passing *arguments* to it.  All given
# key-word arguments are checked for equality in the returned JSON document.
# The check allows partial document comparisons.
def clang_tool(cpp_code, arguments, **checks)
  file = File.tempfile("bindgen-clang-test")
  file.puts(cpp_code)
  file.flush

  tool = ENV["BINDGEN_BIN"]? || Bindgen::Parser::Runner::BINARY_PATH

  # Written by `clang/find_clang.cr` when building the tool.
  cxx_flags = "-std=c++11 -D__STDC_CONSTANT_MACROS -D__STDC_LIMIT_MACROS"
  variables = File.join(__DIR__, "../../clang/variables.yml")
  if File.exists?(variables)
    cxx_flags = YAML.parse(File.read(variables))["llvm_cxx_flags"].as_s
  end
  command = "#{tool} #{file.path} #{arguments} -- " \
            "-x c++ #{cxx_flags} " \
            "-Wno-implicitly-unsigned-literal"

  puts "Command: #{command}" if ENV["VERBOSE"]?
  json_doc = `#{command}`

  # HACK: `JSON.parse` can't read integers exceeding `Int64`, wrap them around.
  json_doc = json_doc.gsub(/(?<=: )\d{19,}(?=[,}])/) { |n| n.to_u64.unsafe_as(Int64).to_s }
  doc = JSON.parse(json_doc)

  checks.each do |path, value|
    object = traverse_path(doc.raw, path)
    check_partial_value(object, value, path.to_s)
  end
rescue error : ClangValidationError
  pp error.document
  raise error
rescue error
  pp doc.raw if doc
  raise error
ensure
  file.try(&.delete) unless ENV["VERBOSE"]?
end

private def traverse_path(document, path)
  path.to_s.split('.').reduce(document) do |base, part|
    if index = part.to_i?
      base.as(Array)[index].raw
    else
      base.as(Hash)[part].raw
    end
  end
rescue error
  raise ClangValidationError.new(document, path, "Couldn't find: #{error}")
end

private def check_partial_value(original, expected, path)
  case expected
  when Hash, NamedTuple
    hash = original.as?(Hash)
    raise ClangValidationError.new(original, path, "Expected a Hash, but got a #{expected.class}") if hash.nil?

    expected.each do |key, expected_child|
      value = hash[key.to_s]?
      value = value.raw if value
      check_partial_value(value, expected_child, "#{path}.#{key}")
    end
  when Array, Tuple
    array = original.as?(Array)
    raise ClangValidationError.new(original, path, "Expected an Array, but got a #{expected.class}") if array.nil?

    if array.size != expected.size
      raise ClangValidationError.new(original, path, "Expected array of size #{expected.size}, but got a size of #{array.size} instead")
    end

    expected.each_with_index do |expected_child, index|
      check_partial_value(array[index].raw, expected_child, "#{path}.#{index}")
    end
  else
    if original != expected
      raise ClangValidationError.new(original, path, "Expected #{expected.inspect}, got #{original.inspect}")
    end
  end
end
