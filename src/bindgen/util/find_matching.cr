module Bindgen
  module Util
    # Mix-in providing a `#find_matching` function.  Used by processors.
    module FindMatching(T)
      # Finds all elements in *list*, whose name matches *regex*.
      #
      # `T#name` is tried first.  If it doesn't match and `T` has a
      # `#qualified_name`, like `Parser::Method`, that one is tried: The capture
      # groups then refer to the qualified name.  This order keeps a *regex*
      # matching both, like `(.*)_init`, from capturing the namespace.
      private def find_matching(regex : String, list : Enumerable(T)) : Array(Tuple(T, Regex::MatchData))
        rx = /^#{regex}$/

        matching = [] of {T, Regex::MatchData}
        list.each do |element|
          match = rx.match(element.name)
          match ||= rx.match(element.qualified_name) if element.responds_to?(:qualified_name)

          matching << {element, match} if match
        end

        matching
      end
    end
  end
end
