require "./spec_helper"

# Runs bindgen on `copy_structs_invalid.yml`, wrapping the classes *names* and
# copying their structure.
# Returns the exit code and the logged error messages.
private def copy_structures(*names) : {Int32, String}
  name = "copy_structs_invalid"
  path = "#{__DIR__}/#{name}.yml"

  yaml = String.build do |b|
    b << File.read(path)
    b << "\nclasses:\n"
    b << "  Wrapped: Wrapped\n"
    b << "  Point: Point\n"
    names.each do |type|
      b << "  #{type}: #{type}\n" unless type == "Wrapped"
    end

    b << "\ntypes:\n"
    b << "  Point: { copy_structure: true, generate_binding: false, generate_wrapper: false }\n"
    names.each do |type|
      b << "  #{type}: { copy_structure: true, generate_binding: false, generate_wrapper: false }\n"
    end
  end

  code = 0
  errors = Log::MemoryBackend.new
  Log.builder.bind("bindgen.*", :error, errors)

  begin
    Dir.cd(__DIR__) do
      ENV["SPEC_NAME"] = name
      config = Bindgen::ConfigReader.from_yaml(Bindgen::Configuration, yaml, path)
      code = Bindgen::Tool.new(__DIR__, config, show_stats: false).run!
    end
  ensure
    Log.builder.unbind("bindgen.*", :error, errors)
  end

  {code, errors.entries.join("\n", &.message)}
end

describe "copied structure validation" do
  it "accepts built-in, enumeration, copied and pointer members" do
    code, errors = copy_structures("Valid")
    errors.should eq("")
    code.should eq(0)

    output = File.read("#{__DIR__}/tmp/copy_structs_invalid.cr")
    output.should contain("point : Point\n")
    output.should contain("wrapped_ptr : Wrapped*\n")
    output.should contain("c_string : UInt8*\n")
  end

  it "rejects a std::string member" do
    code, errors = copy_structures("StringMember")
    code.should eq(1)
    errors.should contain(%(Can't copy structure of class "StringMember"))
    errors.should contain(%(field "name"))
    errors.should contain("std::string")
  end

  it "rejects a pointer to a std::string" do
    code, errors = copy_structures("StringPointerMember")
    code.should eq(1)
    errors.should contain(%(Can't copy structure of class "StringPointerMember"))
    errors.should contain(%(field "name"))
    errors.should contain("std::string *")
  end

  it "rejects a container member" do
    code, errors = copy_structures("ContainerMember")
    code.should eq(1)
    errors.should contain(%(Can't copy structure of class "ContainerMember"))
    errors.should contain(%(field "mount_options"))
    errors.should contain("std::vector<std::string>")
  end

  it "rejects an instantiated container member" do
    code, errors = copy_structures("InstantiatedContainerMember")
    code.should eq(1)
    errors.should contain(%(Can't copy structure of class "InstantiatedContainerMember"))
    errors.should contain(%(field "numbers"))
  end

  it "rejects a member of a class which isn't copied" do
    code, errors = copy_structures("WrappedMember")
    code.should eq(1)
    errors.should contain(%(Can't copy structure of class "WrappedMember"))
    errors.should contain(%(field "wrapped"))
  end

  it "rejects an array member of a class which isn't copied" do
    code, errors = copy_structures("WrappedArrayMember")
    code.should eq(1)
    errors.should contain("Struct WrappedArrayMember: Field wrapped is a C array of user type")
  end

  it "rejects a pointer to an unknown type" do
    code, errors = copy_structures("UnknownPointerMember")
    code.should eq(1)
    errors.should contain("Struct UnknownPointerMember: Field opaque has unreachable type Opaque")
  end

  it "rejects such members in a union" do
    code, errors = copy_structures("ContainerUnion")
    code.should eq(1)
    errors.should contain(%(Can't copy structure of class "ContainerUnion"))
    errors.should contain(%(field "numbers"))
  end

  it "accepts a member whose class is copied too" do
    code, errors = copy_structures("WrappedMember", "Wrapped")
    errors.should eq("")
    code.should eq(0)
  end
end
