module Bindgen
  class FindPath
    # Finds all matches in a list of candidate paths.
    class MatchFinder
      # Eases testing, as we can now expect other code to restrict to Enumerable
      include Enumerable(String)

      @parent : FindPath
      @search_paths : Array(String)?
      @config : PathConfig
      @checkers : Array(Checker)

      # Additional variables to be set by this match.
      getter additional_variables : Hash(String, String)?

      def initialize(@parent, @search_paths, @config, @checkers)
      end

      # Iterates over the set of candidates, yielding for each valid one.
      def each(&)
        @config.try.each do |try|
          run_path_try(try, @search_paths).each do |path|
            if run_path_checkers(path, @config.kind, @checkers)
              yield path
            end
          end
        end

        nil # Not found
      end

      # Tests if *path* matches *kind* and all *checkers*.  Returns `true` on
      # success, or `false` otherwise.
      private def run_path_checkers(path : String, kind, checkers) : Bool
        if kind.exists?(path)
          checkers.all?(&.check(path))
        else
          false
        end
      end

      # Tries to match *path* of type *kind* using *checkers*.
      private def run_path_try(path : String, search_paths) : Array(String)
        pattern = Util.template(path, @parent.root, env: @parent.variables)
        patterns = prefix_search_paths(search_paths, pattern)

        # A path may contain characters special to `Dir[]`, like in
        # `/opt/sdk[1]/include`.  Try those as they are if nothing matched.
        candidates = Dir[patterns]
        candidates.empty? ? patterns : candidates
      end

      # :ditto:
      private def run_path_try(shell : ShellTry, search_paths) : Array(String)
        [run_shell_try(shell)].compact
      end

      # Helper for `#run_path_try`.
      private def run_shell_try(shell : ShellTry) : String?
        command = Util.template(shell.shell, @parent.root, env: @parent.variables)

        output = `#{command}`
        return nil unless $?.success?

        if rx = shell.regex
          regex_capture(rx, output)
        else
          empty_is_nil(output.lines.first?)
        end
      end

      # Tries to match *rx* to *data*, returning the first or zeroth capture
      # group on a successful match.  An empty capture is treated as not
      # matching.
      private def regex_capture(rx : String, data : String) : String?
        regex = Regex.new(rx, FindPath::MULTILINE_OPTION)
        match = regex.match(data)

        if match
          found = match[1]? || match[0]
          empty_is_nil(found.strip)
        end
      end

      # Returns *string* only if it's not empty nor nil.
      private def empty_is_nil(string) : String?
        if string.nil? || string.empty?
          nil
        else
          string
        end
      end

      # Expands *search_paths* for *path*
      private def prefix_search_paths(search_paths, path : String) : Array(String)
        if search_paths.nil? || search_paths.empty?
          [path]
        elsif path.starts_with?('/')
          [path]
        else
          search_paths.map { |x| "#{x}/#{path}" }
        end
      end
    end
  end
end
