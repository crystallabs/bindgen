module Bindgen
  module Processor
    # Processor wrapping single- and multiple-inheritance.
    #
    # Only non-private wrapped classes are possible candidates for this.  Of
    # all candidates, the first one is chosen as parent class in Crystal. All
    # others get a `#as_X() : X` casting method.
    #
    # Take this C++ class: `class Foo : public Bar, public Baz`
    # If both `Bar` and `Baz` are wrapped, the resulting Crystal wrapper will
    # look like this:
    #
    # ```
    # class Foo < Bar # First one is inherited
    #   def as_baz : Baz
    #     ...
    #   end # Later ones converted
    # end
    # ```
    class Inheritance < Base
      def visit_class(klass : Graph::Class)
        # Mark abstract classes
        klass.abstract = klass.origin.abstract?

        # Find all non-private, wrapped bases.
        bases = klass.origin.bases.reject { |b| b.private? || b.virtual? }
        wrapped = wrapped_classes(bases)

        unless wrapped.empty?
          # We inherit the first wrapped base-class in Crystal.
          klass.base_class = Graph::Path.local(from: klass, to: wrapped.first).to_s

          # For all other base-classes, we provide `#as_X` methods.
          if wrapped.size > 1
            add_conversion_methods(klass, wrapped[1..-1])
          end

          copy_virtual_methods(klass, wrapped)
        end

        # Abstract classes can't be directly instantiated.
        add_abstract_impl_class(klass) if klass.abstract?
      end

      # Copies all virtual methods, that are not already in *klass*, from
      # *wrapped*.  This makes `Processor::VirtualOverride`s job much easier,
      # and allows us to generate a proper abstract `Impl` class.
      private def copy_virtual_methods(klass : Graph::Class, wrapped)
        additional_methods = base_virtual_methods(klass.origin, wrapped)

        additional_methods.each do |method|
          if !klass.abstract? && method.pure?
            method = unabstract_method(method)
          end

          Graph::Method.new(
            origin: method,
            name: method.name,
            parent: klass,
          )
        end
      end

      # Finds all virtual methods in the *wrapped* bases of *klass*, which are
      # not implemented in *klass*.
      private def base_virtual_methods(klass, wrapped) : Array(Parser::Method)
        known_virtuals = klass.wrappable_methods.select(&.virtual?)

        wrapped.flat_map do |base|
          base.origin.wrappable_methods.select do |method|
            next unless method.virtual?
            next if known_virtuals.any? { |known| known.equals_virtually?(method) }

            true
          end
        end
      end

      # Adds all conversion methods from *klass* to *bases*.
      private def add_conversion_methods(klass, bases)
        bases.each do |base|
          add_conversion_method(klass, base)
        end
      end

      # Adds a `#as_BASE` method to *klass*.  The name of *base* is demodulized:
      # Asumming a base-name like `Foo::BarBaz`, the method will be called
      # `#as_bar_baz`.
      private def add_conversion_method(klass, base)
        converter = conversion_method(klass, base)
        graph = Graph::Method.new(origin: converter, name: converter.crystal_name, parent: klass)
        pass = Cpp::Pass.new(@db)

        # The Crystal wrapper and bindings will be generated automatically for us later.
        call = CallBuilder::CppCall.new(@db)
        wrapper = CallBuilder::CppWrapper.new(@db)
        target = call.build(converter, body: CastBody.new)

        graph.calls[Graph::Platform::Cpp] = wrapper.build(converter, target)
      end

      # Builds a method converting *from* in *to*.
      private def conversion_method(from, to)
        name, _ = Crystal::Typename.new(@db).wrapper(to.origin.as_type)
        demodulized = name.gsub(/.*::/, "").underscore

        Parser::Method.build(
          name: "AS_#{to.mangled_name}",
          return_type: to.origin.as_type(pointer: 1),
          arguments: [] of Parser::Argument,
          class_name: from.origin.name,
          crystal_name: "as_#{demodulized}",
        )
      end

      # Finds all wrapped classes in *bases*.
      private def wrapped_classes(bases) : Array(Graph::Class)
        nodes = [] of Graph::Class

        bases.each do |base|
          # Ask the type database for the graph node.  The `Graph::Builder` set
          # these initially for us.
          node = @db[base.name]?.try(&.graph_node).as?(Graph::Class)
          nodes << node if node
        end

        nodes
      end

      # Adds a non-abstract `KlassImpl < Klass` class
      private def add_abstract_impl_class(klass)
        impl_class = create_impl_class(klass)
        klass.wrap_class = impl_class
        impl_class.wrapped_class = klass
        impl_class.base_class = klass.name

        klass.nodes.each do |node|
          next unless node.is_a?(Graph::Method)
          next unless node.origin.pure?
          add_unabstract_method(node, impl_class)
        end
      end

      # Creates a non-abstract graph class from *klass*, and adds it to
      # *klass*es parent container.
      private def create_impl_class(klass)
        parent = klass.parent.as(Graph::Container)

        host = parent.platform_specific(Graph::Platform::Crystal)
        Graph::Class.new(
          origin: unabstract_class(klass.origin),
          name: "#{klass.name}Impl",
          parent: host,
        )
      end

      # Adds a non-abstract copy of *method* to *klass*
      private def add_unabstract_method(method, klass)
        graph = Graph::Method.new(
          name: method.name,
          origin: unabstract_method(method.origin),
          parent: klass,
        )

        graph.calls.merge!(method.calls)
      end

      # Returns a non-abstract copy of *method*.
      private def unabstract_method(method)
        return method unless method.pure?

        Parser::Method.new(
          type: method.type,
          name: method.name,
          access: method.access,
          isConst: method.const?,
          isVirtual: method.virtual?,
          isPure: false,
          className: method.className, # Keep original class!
          arguments: method.arguments,
          firstDefaultArgument: method.first_default_argument,
          returnType: method.return_type,
        )
      end

      # Returns a non-abstract copy of *klass*.
      private def unabstract_class(klass)
        base = Parser::BaseClass.new(
          isVirtual: false,
          inheritedConstructor: true,
          name: klass.name,
          access: Parser::AccessSpecifier::Public,
        )

        Parser::Class.new(
          isClass: klass.class?,
          hasDefaultConstructor: klass.has_default_constructor?,
          hasCopyConstructor: klass.has_copy_constructor?,
          isAbstract: false,
          isDestructible: klass.destructible?,
          name: "#{klass.name}Impl",
          byteSize: klass.byteSize,
          bases: [base],
          fields: klass.fields.dup,
          methods: klass.methods.map { |m| unabstract_method(m) },
        )
      end

      # C++ body doing a `static_cast<T*>(_self_)`.
      class CastBody < Call::Body
        def to_code(call : Call, _platform : Graph::Platform) : String
          typer = Cpp::Typename.new
          type_name = typer.full(call.result)
          "static_cast<#{type_name}>(_self_)"
        end
      end
    end
  end
end
