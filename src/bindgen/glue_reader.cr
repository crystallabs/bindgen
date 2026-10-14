module Bindgen
  # Reads glue-code from the `assets/glue.cr` file, for it to be inserted into
  # the generated `.cr` file.
  class GlueReader
    PATH = "#{__DIR__}/../../assets/glue.cr"

    MARKER = "########## SNIP ##########"

    # Returns the glue code from `PATH`, skipping the header.
    def self.read : String
      File.open(PATH) do |file|
        while file.read_line != MARKER
        end

        return file.gets_to_end
      end
    end
  end
end
