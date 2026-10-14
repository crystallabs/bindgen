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
    #
    # Classes with further wrapped bases, and polymorphic classes with wrapped
    # polymorphic ancestors or descendants, get a `#to?(T.class)` method,
    # casting `self` to the wrapper class `T`.  It returns `self` for its own
    # class, calls `#as_X` for the further bases, and casts down to polymorphic
    # sub-classes through a `dynamic_cast`, returning `nil` if the instance
    # isn't a `T`.  The result wraps the same C++ object.  Other types are
    # passed on to the `#to?` of the Crystal superclass, or are a compile-time
    # error.
    #
    # ```
    # x = Bar.create # Returns a `Bar`, which actually is a `Foo`
    # x.to?(Foo)     # => #<Foo:...>
    # x.to?(Baz)     # Compile-time error
    # ```
    class Inheritance < Base
      def initialize(config, db)
        super

        @casts = {} of Graph::Class => ToBody
      end

      def process(graph : Graph::Container, doc : Parser::Document)
        super

        # Casts not handled by a class are passed on to its Crystal superclass.
        @casts.each do |klass, body|
          superclass = klass
          while superclass = crystal_superclass(superclass)
            if @casts.has_key?(superclass)
              body.inherited = true
              break
            end
          end
        end
      end

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

          copy_base_methods(klass, wrapped)

          # Unify the argument types for all virtual methods
          unify_virtual_methods(klass)
        end

        add_downcast_methods(klass)

        # Abstract classes can't be directly instantiated.
        add_abstract_impl_class(klass) if klass.abstract?
      end

      # Copies all virtual methods, that are not already in *klass*, from
      # *wrapped*.  This makes `Processor::VirtualOverride`s job much easier,
      # and allows us to generate a proper abstract `Impl` class.  Also copies
      # the non-virtual methods of all but the first base, as these are not
      # inherited in Crystal.
      private def copy_base_methods(klass : Graph::Class, wrapped)
        additional_methods = base_methods(klass.origin, wrapped)

        # An `Impl` class already has the pure methods, see `#add_abstract_impl_class`
        existing = klass.nodes.compact_map(&.as?(Graph::Method).try(&.origin))

        additional_methods.each do |method|
          next if existing.any?(&.equals_virtually?(method))
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
      # not implemented in *klass*, and all non-virtual methods of the other
      # bases not hidden by *klass*.  Methods of the other bases are moved into
      # *klass*, so their wrappers get the `this` pointer adjusted by C++.
      private def base_methods(klass, wrapped) : Array(Parser::Method)
        # Private overrides count too: C++ can't call those through *klass*.
        known_virtuals = klass.methods.select(&.virtual?)

        list = wrapped.each_with_index.flat_map do |base, index|
          candidates = base.origin.wrappable_methods + ancestor_virtuals(base.origin)
          methods = candidates.select do |method|
            if method.virtual?
              known_virtuals.none? { |known| known.equals_virtually?(method) }
            else
              index > 0 && method.member_method? &&
                klass.methods.none? { |m| m.name == method.name }
            end
          end

          index > 0 ? methods.map { |m| move_method(m, klass.name) } : methods
        end.to_a

        # Like `Parser::Class#wrap_methods`, wrap const-overloads only once.
        Util.uniq_by(list) { |a, b| a.equals_except_const?(b) || a.equals_virtually?(b) }
      end

      # Virtual methods of the wrapped ancestors of *klass* through the first
      # wrapped base, the nearest first, so a Crystal sub-class can override
      # those declared further up too.  The other bases' methods are moved into
      # the class which has them as direct base, see `#base_methods`.
      private def ancestor_virtuals(klass : Parser::Class) : Array(Parser::Method)
        bases = klass.bases.reject { |b| b.private? || b.virtual? }
        return [] of Parser::Method unless base = wrapped_classes(bases).first?

        base.origin.wrappable_methods.select(&.virtual?) + ancestor_virtuals(base.origin)
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

        # The Crystal wrapper and bindings will be generated automatically for us later.
        call = CallBuilder::CppCall.new(@db)
        wrapper = CallBuilder::CppWrapper.new(@db)
        target = call.build(converter, body: CastBody.new)

        graph.calls[Graph::Platform::Cpp] = wrapper.build(converter, target)

        add_cast(klass, base, converter.crystal_name)
      end

      # Adds casts from all polymorphic, wrapped ancestors of *klass* which
      # don't inherit them in Crystal, down to *klass*.
      private def add_downcast_methods(klass)
        return unless klass.origin.polymorphic?
        return if klass.wrapped_class # Skip `Impl` classes
        return unless wrapper_generated?(klass)

        downcast_hosts(klass).each { |host| add_downcast_method(host, klass) }
      end

      # Finds the top-most polymorphic class of each Crystal inheritance chain
      # in the ancestors of *klass*.  All other polymorphic ancestors inherit
      # their casts from one of these.
      private def downcast_hosts(klass) : Array(Graph::Class)
        ancestors = Set(Graph::Class).new
        collect_ancestors(klass, ancestors)

        ancestors.select do |ancestor|
          next false unless ancestor.origin.polymorphic?
          next false unless wrapper_generated?(ancestor)

          superclass = crystal_superclass(ancestor)
          superclass.nil? || !superclass.origin.polymorphic?
        end
      end

      # Collects all wrapped, non-private ancestors of *klass* into *set*.
      private def collect_ancestors(klass, set)
        bases = klass.origin.bases.reject(&.private?)

        wrapped_classes(bases).each do |base|
          collect_ancestors(base, set) if set.add?(base)
        end
      end

      # The wrapped base class *klass* inherits from in Crystal.
      private def crystal_superclass(klass) : Graph::Class?
        bases = klass.origin.bases.reject { |b| b.private? || b.virtual? }
        wrapped_classes(bases).first?
      end

      private def wrapper_generated?(klass)
        @db.try_or(klass.origin.name, true, &.generate_wrapper?)
      end

      # Adds a cast from *host* to *target* doing a `dynamic_cast` in C++.
      private def add_downcast_method(host, target)
        method = Parser::Method.build(
          name: "CAST_#{target.mangled_name}",
          return_type: target.origin.as_type(pointer: 1).make_pointer_nilable.as(Parser::Type),
          arguments: [] of Parser::Argument,
          class_name: host.origin.name,
        )

        # Only the C++ wrapper and the binding are generated for this method,
        # the Crystal wrapper calls it from `#to?`.
        platforms = Graph::Platforms.flags(CrystalBinding, Cpp)
        graph = Graph::Method.new(origin: method, name: method.name, parent: host.platform_specific(platforms))

        call = CallBuilder::CppCall.new(@db)
        wrapper = CallBuilder::CppWrapper.new(@db)
        target_call = call.build(method, body: CastBody.new("bindgen_dynamic_cast"))
        graph.calls[Graph::Platform::Cpp] = wrapper.build(method, target_call)

        binding = CallBuilder::CrystalBinding.new(@db).build(
          method, host.origin.as_type, CallBuilder::CrystalBinding::InvokeBody,
        )
        result = Crystal::Pass.new(@db).from_wrapper(method.return_type)
        code = result.apply_conversion(binding.body.to_code(binding, Graph::Platform::Crystal))

        add_cast(host, target, code)
      end

      # Adds a cast of *klass* to *target* to its `#to?` method, evaluating
      # *code*.  Also makes sure that *target* can be cast to itself.
      private def add_cast(klass, target, code)
        type_name, _ = Crystal::Typename.new(@db).wrapper(target.origin.as_type)
        cast_body(klass).branches[type_name] = code
        cast_body(target)
      end

      # Returns the body of the `#to?` method of *klass*, adding it first if
      # required.
      private def cast_body(klass) : ToBody
        @casts[klass] ||= begin
          type = klass.origin.as_type
          type_name, _ = Crystal::Typename.new(@db).wrapper(type)

          method = Parser::Method.build(
            name: "to?",
            return_type: type,
            arguments: [] of Parser::Argument,
            class_name: klass.origin.name,
            crystal_name: "to?",
          )

          body = ToBody.new
          body.branches[type_name] = "self"

          host = klass.platform_specific(Graph::Platform::Crystal)
          graph = Graph::Method.new(origin: method, name: method.crystal_name, parent: host)
          graph.calls[Graph::Platform::Crystal] = Call.new(
            origin: method,
            name: method.crystal_name,
            arguments: [] of Call::Argument,
            result: Crystal::Pass.new(@db).from_wrapper(type),
            body: body,
          )

          body
        end
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
          const: method.const?,
          virtual: method.virtual?,
          pure: false,
          class_name: method.class_name, # Keep original class!
          arguments: method.arguments,
          first_default_argument: method.first_default_argument,
          return_type: method.return_type,
        )
      end

      # Returns a copy of *method* as member of the class *class_name*.
      private def move_method(method, class_name)
        Parser::Method.new(
          type: method.type,
          name: method.name,
          access: method.access,
          const: method.const?,
          virtual: method.virtual?,
          pure: method.pure?,
          final: method.final?,
          class_name: class_name,
          arguments: method.arguments,
          first_default_argument: method.first_default_argument,
          return_type: method.return_type,
        )
      end

      # Returns a non-abstract copy of *klass*.
      private def unabstract_class(klass)
        base = Parser::BaseClass.new(
          virtual: false,
          inherited_constructor: true,
          name: klass.name,
          access: Parser::AccessSpecifier::Public,
        )

        Parser::Class.new(
          type_kind: klass.type_kind,
          has_default_constructor: klass.has_default_constructor?,
          has_copy_constructor: klass.has_copy_constructor?,
          has_user_declared_constructor: klass.has_user_declared_constructor?,
          abstract: false,
          polymorphic: klass.polymorphic?,
          destructible: klass.destructible?,
          name: "#{klass.name}Impl",
          byte_size: klass.byte_size,
          bases: [base],
          fields: klass.fields.select { |f| !f.static? },
          methods: klass.methods.map { |m| unabstract_method(m) },
        )
      end

      private def unify_virtual_methods(klass)
        klass.origin.wrappable_methods.select(&.virtual?).each do |method|
          # Find the same virtual method in some parent class
          current = klass
          while base = current.origin
                  .bases
                  .reject(&.private?)
                  .reject(&.virtual?)
                  .compact_map { |b| @db[b.name]?.try(&.graph_node).as?(Graph::Class) }.first?
            # Search more equivalent method in base class
            if base_method = base.origin.wrappable_methods
                 .each
                 .select(&.virtual?)
                 .find { |base_method| base_method.equals_virtually?(method) }
              # Found, so unify the arguments ...
              method.merge_args!(base_method)
              # ... and stop (no need to go further up the inheritance tree)
              break
            end
            # Method not found, try next ancestor
            current = base
          end
        end
      end

      # C++ body doing a `static_cast<T*>(_self_)`, or another *cast*.
      class CastBody < Call::Body
        def initialize(@cast = "static_cast")
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          typer = Cpp::Typename.new
          type_name = typer.full(call.result)
          "#{@cast}<#{type_name}>(_self_)"
        end
      end

      # Crystal body of the `#to?(T.class)` method, choosing the cast by `T`.
      class ToBody < Call::Body
        # Code returning the cast instance, by target Crystal type name.
        getter branches = {} of String => String

        # Does the Crystal superclass also have a `#to?` method?
        property? inherited = false

        def to_code(call : Call, platform : Graph::Platform) : String
          String.build do |b|
            b << "def " << call.name << "(_type_ : T.class) forall T\n"
            @branches.each_with_index do |(type_name, code), idx|
              b << (idx == 0 ? "  {% if" : "  {% elsif") << " T == " << type_name << " %}\n"
              b << "    " << code << "\n"
            end

            b << "  {% else %}\n"
            if inherited?
              b << "    super\n"
            else
              b << "    {% raise \"Can't cast \#{@type} to \#{T}\" %}\n"
            end
            b << "  {% end %}\n"
            b << "end\n"
          end
        end
      end
    end
  end
end
