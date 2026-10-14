module Bindgen
  module Processor
    # Base-class for all processors.
    #
    # The processor `Runner` will instantiate all processors first, then call
    # `#process` in order as configured.
    #
    # All processors are automatically made available as their
    # `String#underscore`d name through in the `processors` configuration.
    #
    # If your processor only requires to act on specific graph nodes, you can
    # simply override the corresponding `#visit_X` method.  See `FilterMethods`
    # for an example of this.
    abstract class Base
      macro inherited
        Log = ::Log.for(self)
      end

      include Graph::Visitor

      def initialize(@config : Configuration, @db : TypeDatabase)
      end

      # Runs the processor.  You may change *graph* as you see fit.
      def process(graph : Graph::Container, doc : Parser::Document)
        visit_children(graph)
      end
    end
  end
end
