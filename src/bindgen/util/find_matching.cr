module Bindgen
  module Util
    # Mix-in providing a `#find_matching` function.  Used by processors.
    module FindMatching(T)
      # Finds all elements in *list*, whose name matches *regex*.
      #
      # If `T` has a `#qualified_name`, like `Parser::Method`, it's matched
      # first: The capture groups then refer to the qualified name.  If it
      # doesn't match, `T#name` is tried, so that an element in a namespace is
      # found by its bare name too.
      private def find_matching(regex : String, list : Enumerable(T)) : Array(Tuple(T, Regex::MatchData))
        rx = /^#{regex}$/

        matching = [] of {T, Regex::MatchData}
        list.each do |element|
          match = rx.match(element.qualified_name) if element.responds_to?(:qualified_name)
          match ||= rx.match(element.name)

          matching << {element, match} if match
        end

        matching
      end
    end
  end
end
