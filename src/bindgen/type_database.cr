module Bindgen
  # Database of type mapping data for wrapper-code generation.  Configuration
  # for common (and built-in) C/C++ types is automatically loaded and added.
  class TypeDatabase
    spoved_logger

    # Describes different styles of argument passing.
    enum PassBy
      Original  # Keep the original type
      Reference # Force a C++ reference
      Pointer   # Force a C++ pass-by-pointer
      Value     # Force a C++ pass-by-value
    end

    # YAML converter for building a regex from an array of strings.  The regex
    # is the union of the individual string patterns.
    module ArrayRegexConverter
      def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Regex
        Regex.union(Array(String).new(ctx, node).map(&->Regex.new(String)))
      end
    end

    # YAML converter for building a conversion template from a string.
    module ConversionTemplateConverter
      def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Template::Base
        Template.from_string(Union(String, Nil).new(ctx, node), simple: false)
      end
    end

    # Configuration of instance variables.
    class InstanceVariableConfig
      include YAML::Serializable

      # Mapping from member name patterns to configurations.
      alias Collection = Hash(Regex, InstanceVariableConfig)

      # Rename the property methods. Supports regex backreferences.
      property rename : String? = nil

      # Ignore the property methods for this data member.
      property ignore = false

      # Whether the null pointer can be assigned to this data member.
      property nilable = false

      def initialize(*, @rename = nil, @ignore = false, nilable = false)
      end
    end

    # Configuration of types, used in `Configuration#types` (The `types:` map
    # in YAML).  See `TypeDatabase::Configuration`.
    class TypeConfig
      include YAML::Serializable

      # Ignore any and all methods using this type anywhere.
      property? ignore = false

      # Semantics of the type (Kind overwrite)
      property kind = Bindgen::Parser::Type::Kind::Class

      # The crystal name of this type.
      property crystal_type : String?

      # The C++ type to pass it around.
      property cpp_type : String?

      # The type used in Crystal, but only in the `lib` binding.
      property binding_type : String?

      # Template code ran to turn the real C++ type into the crystal type.
      @[YAML::Field(converter: Bindgen::TypeDatabase::ConversionTemplateConverter)]
      property from_cpp : Template::Base = Bindgen::Template::None.new

      # Template code ran to turn the crystal type into the real C++ type.
      @[YAML::Field(converter: Bindgen::TypeDatabase::ConversionTemplateConverter)]
      property to_cpp : Template::Base = Bindgen::Template::None.new

      # Converter for this type in Crystal.  Takes precedence over the
      # `#to_crystal` and `#from_crystal` fields.
      property converter : String?

      # Template code ran to turn the binding type to Crystal.
      @[YAML::Field(converter: Bindgen::TypeDatabase::ConversionTemplateConverter)]
      property to_crystal : Template::Base = Bindgen::Template::None.new

      # Template code ran to turn the Crystal type for the binding.
      @[YAML::Field(converter: Bindgen::TypeDatabase::ConversionTemplateConverter)]
      property from_crystal : Template::Base = Bindgen::Template::None.new

      # How to pass this type to C++?
      property pass_by = Bindgen::TypeDatabase::PassBy::Original

      # How to pass this type from Crystal?  Defaults to `#pass_by`.
      property wrapper_pass_by : Bindgen::TypeDatabase::PassBy?

      # If sub-classing of this type is allowed, if it's wrapped and has
      # virtual methods.
      property? sub_class = true

      # If the structure (as in, its non-static fields) shall be tried to
      # replicated in Crystal.  Implies `instance_variables: false`.
      # This doesn't support inheritance!
      property? copy_structure = false

      # Treat this type as built-in type in C++ and Crystal.
      property? builtin = false

      # If to generate a wrapper in Crystal.
      property? generate_wrapper = true

      # If to generate bindings in C++ and Crystal.
      property? generate_binding = true

      # If to generate a superclass wrapper in Crystal.
      property? generate_superclass = true

      # Which methods to filter out.
      property ignore_methods = [] of String

      # Which methods to filter out in the superclass wrapper.  A method is
      # ignored if it matches any of the regex patterns specified.
      @[YAML::Field(converter: Bindgen::TypeDatabase::ArrayRegexConverter)]
      property superclass_ignore_methods = Bindgen::Util::FAIL_RX

      # Instance variable configuration.  Each hash key is a regex used to
      # match instance variable names.
      @[YAML::Field(converter: Bindgen::Configuration::InstanceVariablesConverter)]
      property instance_variables = Bindgen::TypeDatabase::InstanceVariableConfig::Collection.new

      # The node this type is represented by in the graph, if any
      @[YAML::Field(ignore: true)]
      property graph_node : Graph::Node?

      # The name of the Crystal container module this type includes, if any.
      # Used by `CrystalContainerOf`.
      @[YAML::Field(ignore: true)]
      property container_type : String?

      def initialize(
        @crystal_type : String? = nil, @cpp_type : String? = nil, @binding_type : String? = nil,
        @from_cpp = Template::None.new, @to_cpp = Template::None.new, @converter = nil,
        @from_crystal = Template::None.new, @to_crystal = Template::None.new,
        @kind = Parser::Type::Kind::Class, @ignore = false,
        @pass_by = PassBy::Original, @wrapper_pass_by : PassBy? = nil,
        @sub_class = true, @copy_structure = false, @generate_wrapper = true,
        @generate_binding = true, @generate_superclass = true,
        @builtin = false, @ignore_methods = [] of String,
        @superclass_ignore_methods = Util::FAIL_RX,
        @instance_variables = InstanceVariableConfig::Collection.new,
        @graph_node = nil, @container_type = nil
      )
      end

      # Type name to use in the Crystal `lib` block.  Namespace operators (`::`)
      # are automatically converted into underscores for types defined in
      # `lib Binding`.
      def lib_type : String?
        typename = if @copy_structure || @builtin || @kind.enum?
                     @binding_type || @crystal_type || @cpp_type
                   else
                     @binding_type || @cpp_type
                   end

        if typename
          parts = typename.split("::").map(&.camelcase)
          in_lib = !@builtin && !@kind.enum?
          parts.join(in_lib ? "_" : "::")
        end
      end

      # Is this type anonymous?
      def anonymous? : Bool
        case @kind
        when .class? then !!@graph_node.as?(Graph::Class).try(&.origin.anonymous?)
        when .enum?  then !!@graph_node.as?(Graph::Enum).try(&.origin.anonymous?)
        else              false
        end
      end

      # Type name to use in the Crystal wrapper.
      def wrapper_type : String?
        @crystal_type || @binding_type
      end

      # Pass-by configuration in wrapper code.  Prefers the `#wrapper_pass_by`
      # value, and falls back to `#pass_by`.
      def crystal_pass_by : PassBy
        @wrapper_pass_by || @pass_by
      end

      # Merges the *other* rules with these rules.  If a rule is set in both
      # rule-sets, the value from *other* wins.
      def merge(other : self) : self
        {% begin %}
          {% ivars = @type.instance_vars %}
          {% for name in ivars %}
            %var{name} = other.@{{ name }}
            %var{name} = @{{ name }} if %var{name}.nil?
          {% end %}

          self.class.new(
            {% for name in ivars %}
              {{ name }}: %var{name},
            {% end %}
          )
        {% end %}
      end
    end

    # Type alias, used in `Configuration#types` (The `types:` map in YAML).  All
    # configuration fields other than `alias_for` are ignored for aliases.
    class TypeAlias
      include YAML::Serializable

      # The underlying type this alias refers to.
      property alias_for : String
    end

    # Path to the built-in type configuration.  This file defines mappings for
    # most-ish built-in (and other common) types in C++.
    BUILTIN_CONFIG_PATH = "#{__DIR__}/../../builtin_types.yml"

    # Configuration, as used in `Bindgen::Configuration#types`
    alias Configuration = Hash(String, TypeAlias | TypeConfig)

    # Helper method to read the built-in type configuration.
    def self.load_builtins : Configuration
      ConfigReader.from_file(Configuration, BUILTIN_CONFIG_PATH)
    end

    @types = Hash(String, TypeConfig).new

    # All defined aliases.  The underlying types never refer to other aliases,
    # as their own aliases are resolved every time a new alias is added.
    @aliases = Hash(String, Parser::Type).new

    getter cookbook : Cpp::Cookbook

    def initialize(config : Configuration, cookbook : String | Cpp::Cookbook, with_builtins = true)
      logger.info { "creating new database" }

      if with_builtins
        builtins = self.class.load_builtins
        config = builtins.merge(config)
      end

      cookbook = Cpp::Cookbook.create_by_name(cookbook) if cookbook.is_a?(String)

      @cookbook = cookbook

      config.each do |name, rules|
        case rules
        when TypeAlias  then add_alias(name, rules.alias_for)
        when TypeConfig then add(name, rules)
        end
      end
    end

    delegate each, to: @types

    # Look up *type* in the database.  If *type* is a `Parser::Type`, the best
    # match will be found by gradually decaying the *type* (See
    # `Parser::Type#decayed`).
    #
    # **Prefer** passing a `Parser::Type` over passing a `String`.
    #
    # Also see `#[]?`.
    def [](type : String | Parser::Type)
      if found = self[type]?
        found
      else
        raise KeyError.new("No rules for type #{type.inspect}")
      end
    end

    # Look up type in the database with the given *name*.  *name* is expected to
    # be the base name of a C++ type.  If you actually have a full type-name
    # instead, use `Parser::Type.parse` first, and pass that instead.
    #
    # **Prefer** passing a `Parser::Type` over passing a `String`.
    def []?(name : String)
      @types[resolve_aliases(name).full_name]?
    end

    # Look up *type* in the database.  The best match will be found by gradually
    # decaying the *type* (See `Parser::Type#decayed`).  This enables the user
    # to write rules for `int *` and `int` without clashes.
    def []?(type : Parser::Type)
      while type
        decayed_type = type.decayed
        if found = @types[resolve_aliases(type).full_name]? || @types[type.base_name]?
          if decayed_type && (parent = @types[decayed_type.full_name]?)
            found = parent.merge(found)
          end

          return found
        end

        type = decayed_type
      end
    end

    # Resolves type aliases referred to by *type* or the name of a *type*.
    # Returns a type without aliases.
    def resolve_aliases(type : Parser::Type | String)
      return type.substitute(@aliases) if type.is_a?(Parser::Type)

      if underlying_type = @aliases[type]?
        underlying_type
      else
        Parser::Type.parse(type).substitute(@aliases)
      end
    end

    # Adds a type *rules* as *name*.  Overwrites any old rules previously added
    # to the same type name.  *name* must not refer to an existing alias.
    #
    # Also see `#get_or_add` to add rules from processors.
    def add(name : String, rules : TypeConfig)
      logger.trace &.emit "adding alias", name: name

      raise "#{name} is already an alias" if @aliases.has_key?(name)
      @types[name] = rules
    end

    # Quickly adds the *rules* to *name*.  Used for **testing** purposes.
    #
    # Also see `#get_or_add` to add rules from processors.
    def add(name : String, **rules)
      add(name, TypeConfig.new(**rules))
    end

    # Adds an alias *name* that refers to the *aliased* type.  *name* must not
    # refer to an existing type or a different alias.  Raises if adding the
    # given alias would result in a recursive alias loop.
    def add_alias(name : String, alias_for aliased : String)
      raise "#{name} is already a type" if @types.has_key?(name)

      if old_alias = @aliases[name]?
        raise "#{name} is already an alias" unless old_alias.full_name == name
      else
        # Resolves all internal aliases.  At this moment, the internal
        # collection of underlying types do not contain any aliases, so any new
        # aliases must come from this addition.

        # Resolve any aliases already present in the given *aliased* type,
        # against the existing aliases.  If the result contains *name*, then a
        # recursive alias is found.
        underlying_type = Parser::Type.parse(aliased).substitute(@aliases)
        if underlying_type.uses_typename?(name)
          raise "Recursive type alias found: " \
                "#{name.inspect} refers to #{underlying_type.full_name.inspect}"
        end

        # If the existing collection of underlying types refer to our newly
        # created alias, resolve them too.
        @aliases = @aliases.to_h do |n, t|
          replaced_t = t.substitute(name, underlying_type)
          if replaced_t.uses_typename?(n)
            raise "Recursive type alias found: " \
                  "#{n.inspect} refers to #{replaced_t.full_name.inspect}"
          end
          {n, replaced_t}
        end

        # Actually add our alias to the type database.
        @aliases[name] = underlying_type
      end
    end

    # Helper, equivalent to calling `#[type]?.try(&.x) || default`
    def try_or(type : Parser::Type | String, default)
      result = self[type]?.try { |x| yield x }

      if result.nil?
        default
      else
        result
      end
    end

    # Returns the rules for *type*.  If none are found, a new `TypeConfig` is
    # inserted, and returned.
    #
    # This is the method you want to use to add or change rules from within
    # processors.
    #
    # **Important**: If *type* is a `Parser::Type`, then its `#base_name` is
    # used - **not** the `#full_name`.  If you want to provide configuration for
    # a specific type, pass the `#full_name` as string.
    def get_or_add(type : Parser::Type | String) : TypeConfig
      type = type.base_name if type.is_a?(Parser::Type)

      if rules = @types[type]?
        rules
      else
        rules = TypeConfig.new
        add(type, rules)
        rules
      end
    end

    # Adds a type configuration to the type database.  If a configuration for
    # this type was set by the user, it's updated - *not* replaced!
    def add_sparse_type(cpp_name : String, crystal_name : String?, kind)
      logger.trace &.emit "adding sparse type", cpp_name: cpp_name, crystal_name: crystal_name

      config = @types[cpp_name]?
      new_config = config.nil?

      config ||= TypeConfig.new

      config.kind = kind if new_config
      config.cpp_type ||= cpp_name
      config.crystal_type ||= crystal_name if config.generate_wrapper?

      add(cpp_name, config)
    end
  end
end
