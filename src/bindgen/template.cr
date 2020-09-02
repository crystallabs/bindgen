require "./template/*"

module Bindgen
  # Conversion templates for `Call::Result`.  They govern how a call result's
  # code should be transformed to become usable under a certain platform.
  module Template
    # Constructs a template from the string *pattern*.  No-op if the *pattern*
    # is `nil`.  If *simple* is true, the resulting template does not support
    # environment variables.
    def self.from_string(pattern : String?, *, simple = false) : Base
      if pattern.nil?
        None.new
      else
        Basic.new(pattern, simple: simple)
      end
    end
  end
end
