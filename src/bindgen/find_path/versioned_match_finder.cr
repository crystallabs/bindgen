module Bindgen
  class FindPath
    # Finds all matches, yielding them in the sorted order going from most to
    # least preferred.
    class VersionedMatchFinder
      include Enumerable(String)

      # Additional variables to be set by this match.
      getter additional_variables : Hash(String, String)?

      def initialize(@finder : Enumerable(String), @version_check : VersionCheck)
      end

      # Iterates over the set of candidates, yielding each candidate in sorted
      # order.
      def each(&)
        candidates = run_version_check
        store_additional_variables(candidates)

        candidates.each do |_, candidate|
          yield candidate
        end
      end

      # Runs the version checker, and returns the sorted list of candidates.
      private def run_version_check
        version_checker = VersionChecker.new(@version_check)

        @finder.each do |path|
          version_checker.check(path)
        end

        version_checker.sorted_candidates
      end

      # Stores the `version:` variable if configured by the user.
      private def store_additional_variables(candidates)
        if variable_name = @version_check.variable
          candidates.first?.try do |version, _|
            @additional_variables = {variable_name => version}
          end
        end
      end
    end
  end
end
