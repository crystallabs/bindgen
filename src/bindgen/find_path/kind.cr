module Bindgen
  class FindPath
    # Kinds of file that we can distinguish.
    enum Kind
      Directory
      File
      Executable

      # Returns `true` only if *path* exists and is of kind `self`.
      def exists?(path : String) : Bool
        case self
        when Directory
          ::Dir.exists?(path)
        when File
          ::File.file?(path)
        when Executable
          ::File.file?(path) && ::File::Info.executable?(path)
        else
          raise "BUG: Unreachable!"
        end
      end
    end
  end
end
