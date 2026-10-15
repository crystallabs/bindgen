module Bindgen
  module Parser
    # Parser YML configuration.  See `Bindgen::Configuration#parser`.
    class Configuration
      include YAML::Serializable

      # Force path to the bindgen clang tool
      getter binary : String?

      # Flags to pass to the compiler verbatim
      getter flags = %w[-x c++ -std=c++11]

      # List of input files.  Only required option.
      getter files : Array(String)

      # List of include paths
      getter includes = [] of String

      # List of defines (default to allow C99 stuff in C++)
      getter defines = %w[__STDC_CONSTANT_MACROS __STDC_LIMIT_MACROS]

      # Copy all comments in front of declarations, not just documentation
      # comments like `///` and `/** */`?
      getter? all_comments = false
    end
  end
end
