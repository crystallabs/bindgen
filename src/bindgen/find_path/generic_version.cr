module Bindgen
  class FindPath
    # Implements generic version comparator. Imported from
    # https://gist.github.com/ZaWertun/5ff96c43bcf87219bb2344633fe3d136
    class GenericVersion
      include Comparable(self)

      getter parts : Array(String)

      def initialize(parts : Array(String | Int32))
        @parts = parts.map(&.to_s)
      end

      def initialize(*parts)
        @parts = parts.to_a.map(&.to_s)
      end

      def to_s(io : IO)
        @parts.join('.', io)
      end

      def <=>(other : self) : Int32
        res = 0
        invert = false
        parts1 = parts
        parts2 = other.parts
        if parts2.size > parts1.size
          parts1, parts2 = parts2, parts1
          invert = true
        end
        parts1.each_with_index do |str1, i|
          res = i < parts2.size ? compare_part(str1, parts2[i]) : 1
          break unless res == 0
        end
        res * (invert ? -1 : 1)
      end

      # Compares two version parts.  Numeric parts compare as numbers and sort
      # after non-numeric ones, which compare as strings.
      private def compare_part(str1, str2) : Int32
        int1 = str1.to_i rescue nil
        int2 = str2.to_i rescue nil
        if int1 && int2
          int1 <=> int2
        elsif int1 && !int2
          1
        elsif !int1 && int2
          -1
        else
          str1 <=> str2
        end
      end

      def self.parse(str : String)
        new(str.split('.'))
      end
    end
  end
end
