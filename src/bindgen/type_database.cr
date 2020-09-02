module Bindgen
  # Database of type mapping data for wrapper-code generation.  Configuration
  # for common (and built-in) C/C++ types is automatically loaded and added.
  class TypeDatabase
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
      YAML.mapping(
        # Ignore any and all methods using this type anywhere.
        ignore: {
          type:    Bool,
          default: false,
        },

        # Semantics of the type (Kind overwrite)
        kind: {
          type:    Parser::Type::Kind,
          default: Parser::Type::Kind::Class,
        },

        # Will copy the definition of the other rule into this one.
        alias_for: {
          type:    String,
          nilable: true,
        },

        # The crystal name of this type.
        crystal_type: {type: String, nilable: true},

        # The C++ type to pass it around.
        cpp_type: {type: String, nilable: true},

        # The type used in Crystal, but only in the `lib` binding.
        binding_type: {type: String, nilable: true},

        # Template code ran to turn the real C++ type into the crystal type.
        from_cpp: {
          type:      Template::Base,
          default:   Template::None.new,
          converter: ConversionTemplateConverter,
        },

        # Template code ran to turn the crystal type into the real C++ type.
        to_cpp: {
          type:      Template::Base,
          default:   Template::None.new,
          converter: ConversionTemplateConverter,
        },

        # Converter for this type in Crystal.  Takes precedence over the
        # `#to_crystal` and `#from_crystal` fields.
        converter: {type: String, nilable: true},

        # Template code ran to turn the binding type to Crystal.
        to_crystal: {
          type:      Template::Base,
          default:   Template::None.new,
          converter: ConversionTemplateConverter,
        },

        # Template code ran to turn the Crystal type for the binding.
        from_crystal: {
          type:      Template::Base,
          default:   Template::None.new,
          converter: ConversionTemplateConverter,
        },

        # How to pass this type to C++?
        pass_by: {
          type:    PassBy,
          default: PassBy::Original,
        },

        # How to pass this type from Crystal?
        wrapper_pass_by: { # Defaults to `@pass_by`
          type:    PassBy,
          nilable: true,
        },

        # If sub-classing of this type is allowed, if it's wrapped and has
        # virtual methods.
        sub_class: {
          type:    Bool,
          default: true,
        },

        # If the structure (as in, its fields) shall be tried to replicated in
        # Crystal.  Implies `instance_variables: false`.
        # This doesn't support inheritance!
        copy_structure: {
          type:    Bool,
          default: false,
        },

        # Treat this type as built-in type in C++ and Crystal.
        builtin: {
          type:    Bool,
          default: false,
        },

        # If to generate a wrapper in Crystal.
        generate_wrapper: {
          type:    Bool,
          default: true,
        },

        # If to generate bindings in C++ and Crystal.
        generate_binding: {
          type:    Bool,
          default: true,
        },

        # If to generate a superclass wrapper in Crystal.
        generate_superclass: {
          type:    Bool,
          default: true,
        },

        # Which methods to filter out.
        ignore_methods: {
          type:    Array(String),
          default: [] of String,
        },

        # Which methods to filter out in the superclass wrapper.  A method is
        # ignored if it matches any of the regex patterns specified.
        superclass_ignore_methods: {
          type:    Regex,
          default: Util::FAIL_RX,
          converter: ArrayRegexConverter,
        },

        # Instance variable configuration.  Each hash key is a regex used to
        # match instance variable names.
        instance_variables: {
          type:      InstanceVariableConfig::Collection,
          default:   InstanceVariableConfig::Collection.new,
          converter: Bindgen::Configuration::InstanceVariablesConverter,
        },
      )

      # The node this type is represented by in the graph, if any
      property graph_node : Graph::Node?

      def initialize(
        @crystal_type = nil, @cpp_type = nil, @binding_type = nil,
        @from_cpp = Template::None.new, @to_cpp = Template::None.new, @converter = nil,
        @from_crystal = Template::None.new, @to_crystal = Template::None.new,
        @kind = Parser::Type::Kind::Class, @ignore = false,
        @pass_by = PassBy::Original, @wrapper_pass_by = nil,
        @sub_class = true, @copy_structure = false, @generate_wrapper = true,
        @generate_binding = true, @generate_superclass = true,
        @builtin = false, @ignore_methods = [] of String,
        @superclass_ignore_methods = Util::FAIL_RX,
        @instance_variables = InstanceVariableConfig::Collection.new,
        @graph_node = nil, @alias_for = nil
      )
      end

      # Shall methods using this type be ignored?
      def ignore? : Bool
        @ignore
      end

      # Type name to use in the Crystal `lib` block.
      def lib_type : String?
        if @copy_structure || @builtin || @kind.enum?
          @binding_type || @crystal_type || @cpp_type
        else
          @binding_type || @cpp_type
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
          {% for name in @type.instance_vars %}
            var_{{name}} = other.{{ name }}
            var_{{name}} = @{{ name }} if var_{{name}}.nil?
          {% end %}

          self.class.new(
            {% for name in @type.instance_vars %}
              {{ name }}: var_{{name}},
            {% end %}
          )
        {% end %}
      end
    end

    # Path to the built-in type configuration.  This file defines mappings for
    # most-ish built-in (and other common) types in C++.
    BUILTIN_CONFIG_PATH = "#{__DIR__}/../../builtin_types.yml"

    # Configuration, as used in `Bindgen::Configuration#types`
    alias Configuration = Hash(String, TypeConfig)

    # Helper method to read the built-in type configuration.
    def self.load_builtins : Configuration
      ConfigReader.from_file(Configuration, BUILTIN_CONFIG_PATH)
    end

    @types : Configuration

    getter cookbook : Cpp::Cookbook

    def initialize(config : Configuration, cookbook : String | Cpp::Cookbook, with_builtins = true)
      if with_builtins
        builtins = self.class.load_builtins
        config = builtins.merge(config)
      end

      cookbook = Cpp::Cookbook.create_by_name(cookbook) if cookbook.is_a?(String)

      @cookbook = cookbook
      @types = config.dup
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

    # Look up *type* in the database.  *type* is expected to be the base name of
    # a C++ type.  If you actually have a full type-name instead, use
    # `Parser::Type.parse` first, and pass that instead.
    #
    # **Prefer** passing a `Parser::Type` over passing a `String`.
    def []?(type : String, recursion_check = nil)
      check_for_alias(@types[type]?, recursion_check)
    end

    # Look up *type* in the database.  The best match will be found by gradually
    # decaying the *type* (See `Parser::Type#decayed`).  This enables the user
    # to write rules for `int *` and `int` without clashes.
    def []?(type : Parser::Type, recursion_check = nil)
      while type
        decayed_type = type.decayed
        if found = check_for_alias(@types[type.full_name]?, recursion_check)
          if decayed_type && (parent = self[decayed_type]?)
            found = parent.merge(found)
          end

          return found
        end

        type = decayed_type
      end
    end

    # Adds a type *rules* as *name*.
    #
    # Also see `#get_or_add` to add rules from processors.
    def add(name : String, rules : TypeConfig)
      @types[name] = rules
    end

    # Quickly adds the *rules* to *name*.  Used for **testing** purposes.
    #
    # Also see `#get_or_add` to add rules from processors.
    def add(name : String, **rules)
      @types[name] = TypeConfig.new(**rules)
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
        @types[type] = rules
        rules
      end
    end

    # Adds a type configuration to the type database.  If a configuration for
    # this type was set by the user, it's updated - *not* replaced!
    def add_sparse_type(cpp_name : String, crystal_name : String?, kind)
      config = @types[cpp_name]?
      new_config = config.nil?

      config ||= TypeConfig.new

      config.kind = kind if new_config
      config.cpp_type ||= cpp_name
      config.crystal_type ||= crystal_name if config.generate_wrapper

      @types[cpp_name] = config
    end

    # Checks if *rules* has an `TypeConfig#alias_for` set.  If so, looks up the
    # rules of that aliased name, and returns it.  Otherwise, returns the given
    # *rules*.
    #
    # The *previous_rules* argument is passed through `#[]?` by
    # `#check_for_alias` to support recursive type-aliasing, while at least
    # detecting direct self-references.
    private def check_for_alias(rules, previous_rules)
      if other_name = rules.try(&.alias_for)
        if previous_rules == rules
          raise "Recursive type-alias found: #{other_name.inspect} is aliased to itself!"
        end

        self[other_name, rules]?
      else
        rules
      end
    end
  end
end
