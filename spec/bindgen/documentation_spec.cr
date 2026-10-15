require "../spec_helper"

# Keeps `CONFIGURATION.md` in sync with the configuration classes and with
# `TEMPLATE.yml`: Each key has to be mentioned in its section.
private ROOT = File.expand_path("#{__DIR__}/../..")

private CONFIGURATION_MD = File.read("#{ROOT}/CONFIGURATION.md")

private TEMPLATE_YML = File.read("#{ROOT}/TEMPLATE.yml")

# Returns the YAML keys of the configuration class *type*.
private def yaml_keys(type : T.class) : Array(String) forall T
  {% begin %}
    {% keys = [] of StringLiteral %}
    {% for ivar in T.instance_vars %}
      {% ann = ivar.annotation(YAML::Field) %}
      {% unless ann && ann[:ignore] %}
        {% keys << ((ann && ann[:key]) || ivar.name.stringify) %}
      {% end %}
    {% end %}
    [{% for key in keys %} {{ key }}, {% end %}] of String
  {% end %}
end

# Returns the text of the section of `CONFIGURATION.md` under *heading*, up to
# the next heading of the same or a higher level.
private def section(heading : String) : String
  level = heading[/^#+/].size
  lines = CONFIGURATION_MD.lines
  start = lines.index(heading) || fail "No heading #{heading.inspect}"

  rest = lines[(start + 1)..]
  stop = rest.index { |line| line =~ /^\#{1,#{level}} / } || rest.size
  rest[0...stop].join('\n')
end

# Returns the keys missing in *text*, as a code span "`key`" or "`key:`".
private def missing_keys(keys, text : String)
  keys.reject { |key| text.includes?("`#{key}`") || text.includes?("`#{key}:`") }
end

# Returns the keys of the mapping at *indent* inside the top-level mapping
# *top_key* of `TEMPLATE.yml`.
private def template_keys(top_key : String, indent : Int32) : Array(String)
  lines = TEMPLATE_YML.lines
  start = lines.index("#{top_key}:") || fail "No #{top_key}: in TEMPLATE.yml"
  rest = lines[(start + 1)..]
  stop = rest.index(&.=~(/^\S/)) || rest.size

  rx = /^ {#{indent}}([a-z_]+):/
  rest[0...stop].compact_map { |line| rx.match(line).try(&.[1]) }.uniq!
end

describe "CONFIGURATION.md" do
  it "has a section for each top-level key" do
    headings = CONFIGURATION_MD.lines.select(&.starts_with?("## ")).join('\n')
    template = TEMPLATE_YML.scan(/^([a-z_]+):/m).map(&.[1])

    missing_keys(yaml_keys(Bindgen::Configuration), headings).should be_empty
    missing_keys(template, headings).should be_empty
  end

  it "has a section for each type rule" do
    headings = section("## `types`").lines.select(&.starts_with?("### "))
    headings = headings.join('\n')
    keys = yaml_keys(Bindgen::TypeDatabase::TypeConfig)
    keys += yaml_keys(Bindgen::TypeDatabase::TypeAlias)

    missing_keys(keys, headings).should be_empty
    missing_keys(template_keys("types", 4), headings).should be_empty
  end

  check_keys = yaml_keys(Bindgen::FindPath::PathCheck) +
               yaml_keys(Bindgen::FindPath::ShellCheck) +
               yaml_keys(Bindgen::FindPath::AnyOfCheck)

  {
    "## `generators`"          => yaml_keys(Bindgen::Configuration::Generator),
    "## `enums`"               => yaml_keys(Bindgen::Configuration::Enum),
    "## `macros`"              => yaml_keys(Bindgen::Configuration::Macro),
    "## `functions`"           => yaml_keys(Bindgen::Configuration::Function),
    "### Function classes"     => yaml_keys(Bindgen::Configuration::FunctionClass),
    "## `containers`"          => yaml_keys(Bindgen::Configuration::Container),
    "## `parser`"              => yaml_keys(Bindgen::Parser::Configuration),
    "### `instance_variables`" => yaml_keys(Bindgen::TypeDatabase::InstanceVariableConfig),
    "### Searching"            => yaml_keys(Bindgen::FindPath::PathConfig),
    "### Checks"               => check_keys,
    "### Version check"        => yaml_keys(Bindgen::FindPath::VersionCheck),
    "### Lists"                => yaml_keys(Bindgen::FindPath::ListConfig),
  }.each do |heading, keys|
    it "describes each key under #{heading}" do
      missing_keys(keys, section(heading)).should be_empty
    end
  end

  it "describes each key of shell tries" do
    keys = yaml_keys(Bindgen::FindPath::ShellTry)
    missing_keys(keys, section("### Searching")).should be_empty
  end

  it "describes each key of TEMPLATE.yml's mappings" do
    {
      "generators" => {"## `generators`", 4},
      "enums"      => {"## `enums`", 4},
      "parser"     => {"## `parser`", 2},
    }.each do |top_key, (heading, indent)|
      missing_keys(template_keys(top_key, indent), section(heading)).should be_empty
    end
  end
end
