module Bindgen
  # Reads glue-code from the `assets/glue.cr` file, for it to be inserted into
  # the generated `.cr` file.
  class GlueReader
    PATH = "#{__DIR__}/../../assets/glue.cr"

    MARKER = "########## SNIP ##########"

    # Lines between these markers need the C++ glue, and are left out of a
    # binding without a `cpp` generator, like one of a C library.
    IF_CPP_MARKER = "########## IF CPP ##########"
    END_IF_MARKER = "########## END IF ##########"

    # Returns the glue code from `PATH`, skipping the header.  Leaves out the
    # parts needing the C++ glue unless *cpp* is set.
    def self.read(cpp : Bool = true) : String
      File.open(PATH) do |file|
        while file.read_line != MARKER
        end

        glue = String.build do |str|
          skipping = false
          file.each_line(chomp: false) do |line|
            case line.strip
            when IF_CPP_MARKER then skipping = !cpp
            when END_IF_MARKER then skipping = false
            else                    str << line unless skipping
            end
          end
        end

        return glue
      end
    end
  end
end
