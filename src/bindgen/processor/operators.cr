module Bindgen
  module Processor
    # Processor performing special handling for overloaded operators.
    #
    # Currently, the handling includes:
    # 1. Removing the integer arguments of overloaded post-increment and
    #    post-decrement operators.
    class Operators < Base
      include Graph::Visitor::MayDelete

      def visit_method(method : Graph::Method)
        Log.trace { "visiting method #{method.diagnostics_path} : #{method.origin.operator?}" }

        if fixed = method.origin.fix_post_succ_or_pred?
          new_node = Graph::Method.new(
            origin: fixed,
            name: method.name,
            parent: method.parent,
          )

          Log.warn { "replacing method #{method.diagnostics_path} origin with #{fixed.binding_method_name}" }

          replace_node(method, with: new_node)
        end
      end

      # Replaces *old_node* from its parent with *new_node*.  Both nodes must
      # belong to the same parent already.
      private def replace_node(old_node, with new_node)
        parent = old_node.parent.as(Graph::Container)
        nodes = parent.nodes

        old_pos = nodes.index(&.same?(old_node)).not_nil!
        new_pos = nodes.index(&.same?(new_node)).not_nil!
        nodes[old_pos] = new_node
        nodes.delete_at(new_pos)
      end
    end
  end
end
