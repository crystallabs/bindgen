module Bindgen
  module Util
    # String prefix utilities
    module Prefix
      # Finds the common prefix length of *strings*, if any.  Returns `0` if the
      # list is empty, or has only one element.  The returned prefix is always
      # at least one character shorter than the shortest string:  Given
      # `[ "Foo", "FooBar" ]`, the returned prefix length is `2` (`Fo`).
      def self.common(strings : Enumerable(String)) : Int32
        return 0 if strings.size < 2

        max_prefix_len = strings.min_of(&.size)
        first_uncommon = (1..max_prefix_len).find(max_prefix_len) do |len|
          prefix = strings.first.to_slice[0, len]
          is_common = strings.all? { |str| str.to_slice[0, len] == prefix }
          !is_common
        end

        first_uncommon - 1
      end
    end
  end
end
