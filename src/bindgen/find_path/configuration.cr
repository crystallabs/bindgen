require "./kind"

module Bindgen
  class FindPath
    alias Configuration = Hash(String, PathConfig)

    # Forces the interpretation of numeric values as String.
    module AlwaysStringConverter
      def self.from_yaml(ctx, node) : String
        if node.is_a?(YAML::Nodes::Scalar)
          node.value
        else
          node.raise "Expected a scalar value, not a #{node.class}"
        end
      end
    end

    # Used in `PathConfig#try` to distinguish a path try from a shell one.
    class ShellTry
      include YAML::Serializable

      # The shell command to run
      @[YAML::Field(converter: Bindgen::FindPath::AlwaysStringConverter)]
      property shell : String
      # An optional regex to grab the path
      property regex : String? = nil

      def initialize(@shell, @regex = nil)
      end
    end

    # A path check testing a specific path.
    class PathCheck
      include YAML::Serializable

      # The sub-path to check for existence.
      @[YAML::Field(converter: Bindgen::FindPath::AlwaysStringConverter)]

      property path : String

      # What the path should be
      property kind : Bindgen::FindPath::Kind = Bindgen::FindPath::Kind::File

      # Optional: What the file should contain
      property contains : String? = nil

      # Treat the contains as regular expression?
      property regex : Bool = false

      def initialize(@path, @kind = Bindgen::FindPath::Kind::File, @contains = nil, @regex = false)
      end
    end

    # A path check testing using a custom shell command.
    class ShellCheck
      include YAML::Serializable

      # The shell command to run
      @[YAML::Field(converter: Bindgen::FindPath::AlwaysStringConverter)]

      property shell : String

      def initialize(@shell)
      end
    end

    # A path check testing using multiple inner checkers.
    class AnyOfCheck
      include YAML::Serializable

      # Inner checkers
      property any_of : Array(PathCheck | ShellCheck)

      def initialize(@any_of)
      end
    end

    # A path check testing the version of a path or program.
    class VersionCheck
      enum Prefer
        Highest
        Lowest
      end

      enum Fallback
        Fail
        Accept
        Prefer
      end

      include YAML::Serializable

      # Min version string
      @[YAML::Field(converter: Bindgen::FindPath::AlwaysStringConverter)]

      property min : String? = nil

      # Max version string
      @[YAML::Field(converter: Bindgen::FindPath::AlwaysStringConverter)]

      property max : String? = nil
      # Variable to store the detected version string in
      property variable : String? = nil
      # Which version to prefer
      property prefer : VersionCheck::Prefer = Bindgen::FindPath::VersionCheck::Prefer::Highest

      # Fallback behaviour if the regex fails.
      property fallback : Bindgen::FindPath::VersionCheck::Fallback = Bindgen::FindPath::VersionCheck::Fallback::Fail

      # Regular expression to grab it from the name
      property regex : String = "-([0-9.]+)$" # Debian-style

      # Custom command to run to figure out the version
      @[YAML::Field(converter: Bindgen::FindPath::AlwaysStringConverter)]

      property command : String? = nil

      def initialize(
        @min = nil, @max = nil, @prefer = Bindgen::FindPath::VersionCheck::Prefer::Highest,
        @fallback = Bindgen::FindPath::VersionCheck::Fallback::Fail, @regex = "-([0-9.]+)$", @command = nil,
      )
      end
    end

    # Configuration for `PathConfig#list`.
    class ListConfig
      include YAML::Serializable

      # Element separator
      property separator : String = Bindgen::FindPath::PATH_SEPARATOR.to_s

      # Element template
      property template : String

      def initialize(@template, @separator = Bindgen::FindPath::PATH_SEPARATOR.to_s)
      end

      def self.default
        new(template: "%")
      end
    end

    # Converts a `Bool | ListConfig` into a `ListConfig | Nil`.
    module ListConfigConverter
      def self.from_yaml(ctx, node) : ListConfig?
        if node.is_a?(YAML::Nodes::Scalar) # A bool?
          if Bool.new(ctx, node)
            ListConfig.default
          else
            nil
          end
        else # A full config
          ListConfig.new(ctx, node)
        end
      end
    end

    # YAML-based configuration.  Used as value for the `#find_paths` option in
    # `Bindgen::Configuration`.
    class PathConfig
      include YAML::Serializable

      # Bindgen::FindPath::Kind of file to find
      property kind : Bindgen::FindPath::Kind = Bindgen::FindPath::Kind::Directory
      # Is this match optional?
      property optional : Bool = false # Mandatory by default

      # Optional: An error message if not found
      property error_message : String? = nil

      # Paths to try

      property try : Array(String | ShellTry) # converter: TryListConverter,

      # Search paths for relative try paths
      property search_paths : Array(String)? = nil

      # Checks to do
      property checks = Array(Bindgen::FindPath::PathCheck | Bindgen::FindPath::ShellCheck | Bindgen::FindPath::AnyOfCheck).new

      # Version check to do
      property version : VersionCheck? = nil
      # List functionality
      @[YAML::Field(converter: Bindgen::FindPath::ListConfigConverter)]
      property list : ListConfig? = nil

      def initialize(
        @try, @kind = Bindgen::FindPath::Kind::Directory, @optional = false, @error_message = nil,
        @checks = [] of (Bindgen::FindPath::PathCheck | Bindgen::FindPath::ShellCheck),
      )
      end
    end
  end
end
