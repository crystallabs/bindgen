module Bindgen
  module Template
    # Base class of the templates.
    abstract class Base
      # Performs a template substitution.
      abstract def template(code : String) : String

      # Is this a no-operation template?
      abstract def no_op? : Bool

      # Combines two templates into one.  The *other* template is run after the
      # current template.
      def followed_by(other : Base) : Base
        return other if no_op?
        return self if other.no_op?
        Sequence.new(self, other)
      end
    end
  end
end
