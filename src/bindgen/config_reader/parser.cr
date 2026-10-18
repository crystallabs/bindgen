module Bindgen
  module ConfigReader
    # Pull parser for YAML configuration files, offering conditional branches
    # and access to external dependencies.
    #
    # **If you want to read a configuration** see `ConfigReader.from_yaml`.
    #
    # This is done by hooking into the pull parser, manually checking for the
    # conditional fields, and applying them accordingly.
    #
    # Apart from this logic, the configuration file is still valid YAML.
    #
    # **Note**: Conditionals and dependencies are *only* supported in
    # *mappings* (`Hash` in Crystal).  Any such syntax encountered in something
    # other than a *mapping* will not trigger any special behaviour.
    #
    # ## Condition syntax
    #
    # YAML documents can define conditional parts in *mappings* by having a
    # conditional key, with *mapping* value.  If the condition matches, the
    # *mapping* value will be transparently embedded.  If it does not match, the
    # value will be transparently skipped.
    #
    # Condition keys look like `if_X` or `elsif_X` or `else`.  `X` is the
    # condition, and it looks like `Y_is_Z` or `Y_match_Z`.  You can also use
    # (one or more) spaces (` `) instead of exactly one underscore (`_`) to
    # separate the words.
    #
    # * `Y_is_Z` is true if the variable Y equals Z case-sensitively.
    # * `Y_isnt_Z` is true if the variable Y doesn't equal Z case-sensitively.
    # * `Y_match_Z` is true if the variable Y is matched by the regular expression
    #   in `Z`.  The regular expression is created case-sensitively.
    # * `Y_newer_or_Z` is true when variable Y is newer or equals (>=) to Z,
    #   variables are treated as versions.
    # * `Y_older_or_Z` is true when variable Y is older or equals (<=) to Z,
    #   variables are treated as versions.
    #
    # A condition block is opened by the first `if`.  Later condition keys can
    # use `elsif` or `else` (or `if` to open a *new* condition block).
    #
    # **Note**: `elsif` or `else` without an `if` will raise an exception.
    #
    # Their behaviour is like in Crystal: `if` starts a condition block, `elsif`
    # starts an alternative condition block, and `else` is used if none of `if` or
    # `elsif` matched.  It's possible to mix condition key-values with normal
    # key-values.
    #
    # **Note**: Conditions can be used in every *mapping*, even in *mappings* of
    # a conditional.  Each *mapping* acts as its own scope.
    #
    # ### Variables
    #
    # Variables are set by the user of the class (Probably through
    # `ConfigReader.from_yaml`).  All variable values are strings.
    #
    # Variable names are **case-sensitive**.  A missing variable will be treated
    # as having an empty value (`""`).
    #
    # ### Examples
    #
    # ```yaml
    # foo: # A normal mapping
    #   bar: 1
    #
    # # A condition: Matches if `platform` equals "arm".
    # if_platform_is_arm: # In Crystal: `if platform == "arm"`
    #   company: ARM et al
    #
    # # You can mix in values between conditionals.  It won't "break" following
    # # elsif or else blocks.
    # not_a_condition: Hello
    #
    # # An elsif: Matches if 1) the previous conditions didn't match
    # # 2) its own condition matches.
    # elsif_platform_match_x86: # In Crystal: `elsif platform =~ /x86/`
    #   company: Many different
    #
    # # An else: Matches if all previous conditions didn't match.
    # else:
    #   company: No idea
    #
    # # At any time, you can start a new if sequence.
    # "if today is friday": # You can use spaces instead of underscores too
    #   hooray: true
    # ```
    #
    # ## Dependencies
    #
    # To modularize the configuration, you can require ("merge") external yaml
    # files from within your configuration.
    #
    # This is triggered by using a key named `<<`, and writing the file name as
    # value: `<<: my_dependency.yml`.  The file-extension can also be omitted:
    # `<<: my_dependency` in which case an `.yml` extension is assumed.
    #
    # The dependency path is relative to the currently processed YAML file.
    #
    # You can also require multiple dependencies into the same *mapping*:
    #
    # ```yaml
    # types:
    #   Something: true # You can mix dependencies with normal fields.
    #   <<: simple_types.yml
    #   <<: complex_types.yml
    #   <<: ignores.yml
    # ```
    #
    # The dependency will be embedded into the open *mapping*: It's transparent
    # to the client code.
    #
    # It's perfectly possible to mix conditionals with dependencies:
    #
    # ```yaml
    # if_os_is_windows:
    #   <<: windows-specific.yml
    # ```
    #
    # ### Deep merge
    #
    # `<<:` embeds the dependency as it is: A key it shares with the mapping
    # keeps only the later value.  `<<+:` instead merges the dependency into
    # what the mapping holds so far, including earlier dependencies: Mappings
    # under the same key are merged recursively, sequences are concatenated,
    # and other values are replaced.  So two files can configure the same
    # type:
    #
    # ```yaml
    # types:
    #   <<: ignores.yml      # QLayout: { ignore_methods: [ trUtf8 ] }
    #   <<+: keep_alive.yml  # QLayout: { keep_alive: [ ^addWidget$ ] }
    #   # QLayout now has both `ignore_methods` and `keep_alive`.
    # ```
    #
    # Keys written after a `<<+:` aren't merged into it, they override as
    # usual.
    #
    # ### Errors
    #
    # An exception will be raised if any of the following occur:
    #
    # * The maximum dependency depth of `10` (`MAX_DEPTH`) is exceeded.
    # * The dependency name contains a dot: `../foo.yml` won't work.
    # * The dependency name is absolute: `/foo/bar.yml` won't work.
    # * `<<+:` is given something other than a file name, like an alias.
    class Parser < YAML::Nodes::Parser
      class Error < YAML::ParseException
        # The file the error occured in
        getter file : String

        def initialize(message, line, column, @file)
          super("In #{@file}: #{message}", line, column)
        end

        def self.from(err : YAML::ParseException, file : String)
          new(err.message, err.line_number, err.column_number, file)
        end
      end

      # Maximum dependency load depth.
      MAX_DEPTH = 10

      # Default loader for dependencies.
      class_property loader : Loader = Loader.new

      # Evaluator for conditionals.
      getter evaluator : ConditionEvaluator

      # Instance local loader
      getter loader : Loader

      # Path to the root YAML file.
      getter path : String

      # Parser depth, bounded by `MAX_DEPTH`
      getter depth : Int32

      def initialize(content : String | IO, @evaluator : ConditionEvaluator, @path, @loader = @@loader, @depth = 1)
        super(content)
      end

      # Loads and parses a dependency by *path*.
      protected def load_dependency(path : String) : YAML::Nodes::Node
        parser = open_dependency(path)
        parser.parse.nodes.first
      end

      # Loads the dependency at *path* using the `#loader`.
      protected def open_dependency(path : String)
        if @depth >= MAX_DEPTH
          ::raise Error.new("Max dependency depth of #{MAX_DEPTH} exceeded", 0, 0, @path)
        end

        content, full_path = @loader.load(@path, path)
        self.class.new(
          content: content,
          evaluator: @evaluator,
          path: full_path,
          loader: @loader,
          depth: @depth + 1
        )
      end

      # Reimplementation: Add support for `<<: file/path.yml` while retaining
      # support for `<<: *ALIAS`.
      protected def parse_mapping
        mapping = anchor new_mapping
        @pull_parser.read_mapping_start

        parse_mapping_noclose(mapping)
        end_value(mapping)

        mapping
      end

      # Recursive version of `#parse_mapping` capable of handling conditionals.
      protected def parse_mapping_noclose(mapping)
        state = ConditionState::AwaitingIf

        until @pull_parser.kind.mapping_end?
          key = parse_node

          if key.is_a?(YAML::Nodes::Scalar) && @evaluator.conditional?(key.value)
            match, state = @evaluator.evaluate(key.value, state)

            if match
              @pull_parser.read_mapping_start
              parse_mapping_noclose(mapping)
            else
              @pull_parser.skip
            end
          else
            value = parse_node
            update_mapping(mapping, key, value)
          end
        end

        @pull_parser.read_next # Consume MAPPING_END
      rescue err : ConditionEvaluator::Error
        ::raise Error.new(err.message, @pull_parser.start_line, @pull_parser.start_column, @path)
      end

      # Key embedding a dependency, like YAML's merge key.
      MERGE_KEY = "<<"

      # Key deep-merging a dependency into the mapping.
      DEEP_MERGE_KEY = "<<+"

      # Adds the *key*-*value* pair to *mapping*.
      protected def update_mapping(mapping, key, value)
        if key.is_a?(YAML::Nodes::Scalar) && value.is_a?(YAML::Nodes::Scalar) && key.value == MERGE_KEY
          value = load_dependency(value.value)
        elsif key.is_a?(YAML::Nodes::Scalar) && key.value == DEEP_MERGE_KEY
          unless value.is_a?(YAML::Nodes::Scalar)
            ::raise Error.new("#{DEEP_MERGE_KEY} needs the name of a file", key.start_line, key.start_column, @path)
          end

          dependency = load_dependency(value.value)
          unless dependency.is_a?(YAML::Nodes::Mapping)
            ::raise Error.new("#{DEEP_MERGE_KEY}: #{value.value} isn't a mapping", key.start_line, key.start_column, @path)
          end

          deep_merge(mapping, dependency)
          return
        end

        add_to_mapping(mapping, key, value)
      end

      # Merges *source* into *target*, see "Deep merge" above.  Entries of
      # *source* behind a `<<` are merged as if written in place.
      protected def deep_merge(target : YAML::Nodes::Mapping, source : YAML::Nodes::Mapping)
        source.each do |key, value|
          if merge_key?(key)
            merged_mappings(value).each { |mapping| deep_merge(target, mapping) }
            next
          end

          found = find_last(target, key)
          existing = found.try { |mapping, index| mapping.nodes[index + 1] }

          if existing.is_a?(YAML::Nodes::Mapping) && value.is_a?(YAML::Nodes::Mapping)
            deep_merge(existing, value)
          elsif existing.is_a?(YAML::Nodes::Sequence) && value.is_a?(YAML::Nodes::Sequence)
            value.nodes.each { |node| existing << node }
          elsif found
            mapping, index = found
            mapping.nodes[index + 1] = value
          else
            target[key] = value
          end
        end
      end

      # Returns the mapping holding the last entry for *key* in *target*, and
      # the index of its key node.  Looks into mappings embedded through `<<`,
      # as `YAML::Schema::Core.each` later reads them in place.
      protected def find_last(target : YAML::Nodes::Mapping, key : YAML::Nodes::Node) : {YAML::Nodes::Mapping, Int32}?
        return unless key.is_a?(YAML::Nodes::Scalar)
        found = nil

        0.step(by: 2, to: target.nodes.size - 1) do |index|
          entry_key = target.nodes[index]
          if merge_key?(entry_key)
            merged_mappings(target.nodes[index + 1]).each do |mapping|
              found = find_last(mapping, key) || found
            end
          elsif entry_key.is_a?(YAML::Nodes::Scalar) && entry_key.value == key.value
            found = {target, index}
          end
        end

        found
      end

      private def merge_key?(key : YAML::Nodes::Node) : Bool
        key.is_a?(YAML::Nodes::Scalar) && key.value == MERGE_KEY
      end

      # The mappings a `<<` *value* embeds: A mapping, or a sequence of them.
      private def merged_mappings(value : YAML::Nodes::Node) : Array(YAML::Nodes::Mapping)
        value = value.value || return [] of YAML::Nodes::Mapping if value.is_a?(YAML::Nodes::Alias)

        case value
        when YAML::Nodes::Mapping  then [value]
        when YAML::Nodes::Sequence then value.nodes.select(YAML::Nodes::Mapping)
        else                            [] of YAML::Nodes::Mapping
        end
      end

      protected def add_to_mapping(mapping, key, value)
        if value.is_a?(Hash)
          mapping.merge!(value)
        elsif value.is_a?(Array) && value.all?(Hash)
          value.each do |elem|
            mapping.merge!(elem.as(Hash))
          end
        else
          mapping[key] = value
        end
      end
    end
  end
end
