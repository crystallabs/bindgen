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
    #
    # Every wrapper class gets the Crystal class method
    # `Graph::Class::DISCOVER_METHOD`, see SPEC.md §2.3.7, which wraps a
    # pointer in the Crystal object which constructed the object, if any, and
    # else in a new wrapper.  A polymorphic class with wrapped sub-classes in
    # Crystal gets type discovery too: a C++ `DISCOVER` function finding the
    # wrapper class of the dynamic type of an object, which the method wraps
    # in.  `Crystal::Pass#from_wrapper` converts a pointer or reference result,
    # and the argument of a callback, through it: `x` above is a `Foo` already.
    class Inheritance < Base
      def initialize(config, db)
        super

        @casts = {} of Graph::Class => ToBody
        @all_classes = Parser::Class::Collection.new
        @unified = Set(UInt64).new # `object_id`s of the unified methods
        # The classes getting a `DISCOVER_METHOD`, in order.
        @identified = [] of Graph::Class
        # The wrapped Crystal sub-classes of a polymorphic class, with their
        # distance from it.
        @discovered = {} of Graph::Class => Array({Graph::Class, Int32})
      end

      def process(graph : Graph::Container, doc : Parser::Document)
        @all_classes = doc.classes
        super

        add_discovery_methods

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
        superclass, others = split_bases(klass.origin)

        if superclass || others.present?
          # We inherit one wrapped base-class in Crystal.
          if superclass
            klass.base_class = Graph::Path.local(from: klass, to: superclass).to_s
          end

          # For all other base-classes, we provide `#as_X` methods.
          add_conversion_methods(klass, others)

          copy_base_methods(klass, superclass, others)
        end

        # Unify the arguments of all virtual methods with the overridden ones
        unify_virtual_methods(klass.origin)

        add_downcast_methods(klass)
        register_discovery(klass)

        # Abstract classes can't be directly instantiated.
        add_abstract_impl_class(klass) if klass.abstract?

        super # Nested classes
      end

      # Copies all virtual methods, that are not already in *klass*, from
      # *wrapped*.  This makes `Processor::VirtualOverride`s job much easier,
      # and allows us to generate a proper abstract `Impl` class.  Also copies
      # the non-virtual methods of all but the first base, as these are not
      # inherited in Crystal.
      private def copy_base_methods(klass : Graph::Class, superclass, others)
        additional_methods = base_methods(klass.origin, superclass, others)

        # An `Impl` class already has the pure methods, see `#add_abstract_impl_class`
        existing = klass.nodes.compact_map(&.as?(Graph::Method).try(&.origin))

        # Filtered like the methods of the class itself, see `FilterMethods`.
        filter = FilterMethods.new(@config, @db)

        additional_methods.each do |method|
          next if existing.any?(&.equals_virtually?(method))
          next if filter.filtered?(method)
          # A private override implements a pure method, for C++ callers
          # through the base: `QAbstractListModel::parent`.
          if method.pure? && (!klass.abstract? || private_override?(klass.origin, method))
            method = unabstract_method(method)
          end

          Graph::Method.new(
            origin: method,
            name: method.name,
            parent: klass,
          )
        end
      end

      # Finds all virtual methods in the wrapped bases of *klass*, which are
      # not implemented in *klass*, and all non-virtual methods of the *others*
      # bases not hidden by *klass*.  Methods of the *others* are moved into
      # *klass*, so their wrappers get the `this` pointer adjusted by C++.
      private def base_methods(klass, superclass, others) : Array(Parser::Method)
        # Private overrides count too: C++ can't call those through *klass*.
        # The public declaration in the superclass is still callable through
        # it, and dispatches to the override, so that one is copied instead;
        # the other bases' methods are moved into *klass*, so there it can't.
        known_virtuals = klass.methods.select(&.virtual?)
        known_public_virtuals = known_virtuals.reject(&.private?)

        bases = others.map { |base| {base, true} }
        bases.unshift({superclass, false}) if superclass

        # `wrap_methods` has the overloads a default argument splits a method
        # into, which an `Impl` class of an abstract base needs too.
        list = bases.flat_map do |base, moved|
          candidates = base.origin.wrap_methods + ancestor_virtuals(base.origin)
          methods = candidates.select do |method|
            if method.virtual?
              known = moved ? known_virtuals : known_public_virtuals
              known.none?(&.equals_virtually?(method))
            else
              moved && method.member_method? &&
                klass.methods.none? { |m| m.name == method.name }
            end
          end

          moved ? methods.map { |m| move_method(m, klass.name) } : methods
        end

        # Like `Parser::Class#wrap_methods`, wrap const-overloads only once.
        Util.uniq_by(list) { |a, b| a.equals_except_const?(b) || a.equals_virtually?(b) }
      end

      # Virtual methods of the wrapped ancestors of *klass* through the first
      # wrapped base, the nearest first, so a Crystal sub-class can override
      # those declared further up too.  The other bases' methods are moved into
      # the class which has them as direct base, see `#base_methods`.
      private def ancestor_virtuals(klass : Parser::Class) : Array(Parser::Method)
        return [] of Parser::Method unless base = split_bases(klass)[0]

        base.origin.wrap_methods.select(&.virtual?) + ancestor_virtuals(base.origin)
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
        split_bases(klass.origin)[0]
      end

      # Splits the non-private, non-virtual wrapped bases of *klass* into the
      # one it inherits from in Crystal, if any, and the others.  A pointer to
      # *klass* is passed unchanged to the methods of its Crystal superclass, so
      # that one must be at offset 0: The first such wrapped base.
      private def split_bases(klass : Parser::Class) : {Graph::Class?, Array(Graph::Class)}
        bases = klass.bases.reject { |b| b.private? || b.virtual? }
        primary = bases.find { |b| b.offset == 0 && wrapped_classes([b]).present? }

        superclass = primary.try { |b| wrapped_classes([b]).first? }
        {superclass, wrapped_classes(bases.reject(&.same?(primary)))}
      end

      private def wrapper_generated?(klass)
        @db.try_or(klass.origin.name, true, &.generate_wrapper?)
      end

      # Adds a cast from *host* to *target* doing a `dynamic_cast` in C++.
      private def add_downcast_method(host, target)
        return_type = target.origin.as_type(pointer: 1).make_pointer_nilable ||
                      raise "BUG: A pointer to #{target.origin.name} must be nilable"

        method = Parser::Method.build(
          name: "CAST_#{target.mangled_name}",
          return_type: return_type,
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
        invoke = binding.body.to_code(binding, Graph::Platform::Crystal)

        # The conversion is built when the code is generated: whether *target*
        # has type discovery, or an `Impl` class as an abstract class, is known
        # once every class is visited.
        code = -> do
          Crystal::Pass.new(@db).from_wrapper(method.return_type).apply_conversion(invoke)
        end

        add_cast(host, target, code)
      end

      # Adds a cast of *klass* to *target* to its `#to?` method, evaluating
      # *code*.  Also makes sure that *target* can be cast to itself.
      private def add_cast(klass, target, code : String | Proc(String))
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

      # Registers *klass* for a `DISCOVER_METHOD`, and for the type discovery
      # of its polymorphic ancestors in Crystal, see `#add_discovery_method`.
      private def register_discovery(klass : Graph::Class)
        return if klass.wrapped_class # Skip `Impl` classes
        return unless wrapper_generated?(klass)
        return unless rules = @db[klass.origin.name]?
        return if !rules.kind.class? || rules.copy_structure?

        @identified << klass
        return unless klass.origin.polymorphic?

        depth = 0
        ancestor = klass
        while ancestor = crystal_superclass(ancestor)
          depth += 1
          next unless ancestor.origin.polymorphic? && wrapper_generated?(ancestor)

          list = (@discovered[ancestor] ||= [] of {Graph::Class, Int32})
          list << {klass, depth}
        end
      end

      # Adds the `DISCOVER_METHOD` of each registered class, with the type
      # discovery of those with registered sub-classes.
      private def add_discovery_methods
        @identified.each do |klass|
          # The deepest first, so the first `dynamic_cast` matching is to the
          # most derived class.
          list = @discovered[klass]? || [] of {Graph::Class, Int32}
          descendants = list.sort_by { |node, depth| {-depth, node.origin.name} }.map(&.first)
          add_discovery_method(klass, descendants)
        end
      end

      # Adds the Crystal class method `Graph::Class::DISCOVER_METHOD` to
      # *klass*, see SPEC.md §2.3.7, wrapping a pointer to *klass* in the
      # Crystal object which constructed the object, or in a new wrapper.  With
      # *descendants*, the C++ `DISCOVER` function tells the wrapped class of
      # the dynamic type of the object, one of them, which the new wrapper is
      # of, else it is of *klass* itself.
      private def add_discovery_method(klass : Graph::Class, descendants : Array(Graph::Class))
        klass.type_discovery = true
        fun_name = add_discover_function(klass, descendants) unless descendants.empty?

        type = klass.origin.as_type.never_nil
        crystal_method = Parser::Method.build(
          name: Graph::Class::DISCOVER_METHOD,
          return_type: type,
          arguments: [] of Parser::Argument,
          class_name: klass.origin.name,
          type: Parser::Method::Type::StaticMethod,
          crystal_name: Graph::Class::DISCOVER_METHOD,
        )

        host = klass.platform_specific(Graph::Platform::Crystal)
        node = Graph::Method.new(origin: crystal_method, name: crystal_method.crystal_name, parent: host)
        node.calls[Graph::Platform::Crystal] = Call.new(
          origin: crystal_method,
          name: crystal_method.crystal_name,
          arguments: [] of Call::Argument,
          result: Crystal::Pass.new(@db).from_wrapper(type, discover: false),
          body: DiscoverCrystalBody.new(@db, fun_name, klass, descendants),
        )
      end

      # Adds the C++ `DISCOVER` function of *klass* with the table of its
      # *descendants*, see `DiscoverCppBody`, and returns its name.
      private def add_discover_function(klass : Graph::Class, descendants : Array(Graph::Class)) : String
        method = Parser::Method.build(
          name: "DISCOVER",
          return_type: Parser::Type.parse("void", 1),
          arguments: [
            Parser::Argument.new("bg_class", Parser::Type.parse("int", 1)),
            Parser::Argument.new("bg_crystal", Parser::Type.parse("void", 2)),
          ],
          class_name: klass.origin.name,
        )

        # Only the C++ wrapper and the binding are generated for this method,
        # the Crystal class method calls it.
        platforms = Graph::Platforms.flags(CrystalBinding, Cpp)
        graph = Graph::Method.new(origin: method, name: method.name, parent: klass.platform_specific(platforms))

        pass = Cpp::Pass.new(@db)
        arguments = pass.arguments_to_cpp(method.arguments)
        arguments.unshift(Cpp::Argument.self(Parser::Type.parse(klass.origin.name, 1)))
        graph.calls[Graph::Platform::Cpp] = Call.new(
          origin: method,
          name: method.mangled_name,
          arguments: arguments,
          result: pass.to_crystal(method.return_type),
          body: DiscoverCppBody.new(klass, descendants),
        )

        method.mangled_name
      end

      # Builds a method converting *from* in *to*.
      private def conversion_method(from, to)
        name, _ = Crystal::Typename.new(@db).wrapper(to.origin.as_type)
        demodulized = name.gsub(/.*::/, "").underscore

        Parser::Method.build(
          name: "AS_#{to.mangled_name}",
          return_type: to.origin.as_type(pointer: 1).never_nil, # A cast of self
          arguments: [] of Parser::Argument,
          class_name: from.origin.name,
          crystal_name: "as_#{demodulized}",
        )
      end

      # Does *klass* override *method* privately?
      private def private_override?(klass : Parser::Class, method : Parser::Method) : Bool
        klass.find_parent_method(method).try(&.private?) || false
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
          deprecated: method.deprecated?,
          origin: method.origin, # A variant of its origin stays one
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
          deprecated: method.deprecated?,
          origin: method.origin, # A variant of its origin stays one
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

      # Unifies the arguments of the virtual methods of *klass* with those of
      # the methods they override: An override is named like the overridden
      # method, and takes its default values where it has none, like
      # `QGraphicsTextItem::paint` dropping the `widget = nullptr` of
      # `QGraphicsItem::paint`.  C++ takes the default from the static type,
      # and Crystal requires an implementation of an abstract method to accept
      # its calls.  All C++ ancestors count, wrapped or not, through all bases.
      private def unify_virtual_methods(klass : Parser::Class)
        klass.wrappable_methods.each do |method|
          unify_virtual_method(klass, method) if method.virtual?
        end
      end

      # Unifies the arguments of *method* of *klass* with the method it
      # overrides, which first gets unified with its overridden one.
      private def unify_virtual_method(klass : Parser::Class, method : Parser::Method)
        return unless @unified.add?(method.object_id)
        return unless found = overridden_method(klass, method)

        base, base_method = found
        unify_virtual_method(base, base_method)
        method.merge_args!(base_method)
      end

      # Finds the nearest method *method* of *klass* overrides, searching the
      # bases depth-first in their declaration order.
      private def overridden_method(klass : Parser::Class, method : Parser::Method) : {Parser::Class, Parser::Method}?
        klass.bases.each do |base|
          next unless base_class = @all_classes[base.name]?

          if found = base_class.methods.find { |m| m.virtual? && m.equals_virtually?(method) }
            return {base_class, found}
          end

          if found = overridden_method(base_class, method)
            return found
          end
        end

        nil
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
        # Code returning the cast instance, by target Crystal type name, or a
        # `Proc` building it when the code is generated.
        getter branches = {} of String => String | Proc(String)

        # Does the Crystal superclass also have a `#to?` method?
        property? inherited = false

        def to_code(call : Call, platform : Graph::Platform) : String
          String.build do |b|
            b << "def " << call.name << "(_type_ : T.class) forall T\n"
            @branches.each_with_index do |(type_name, code), idx|
              code = code.call if code.is_a?(Proc)
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

      # C++ body of the `DISCOVER` function of a class, see
      # `#add_discovery_method`: a `BindgenTypeDiscovery` table of its
      # *descendants*, numbered from 1 in their order.
      class DiscoverCppBody < Call::Body
        def initialize(@klass : Graph::Class, @descendants : Array(Graph::Class))
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          typer = Cpp::Typename.new
          formatter = Cpp::Format.new
          base = @klass.origin.name
          self_var, id_var, crystal_var = call.arguments.map(&.name)

          String.build do |b|
            b << %[extern "C" ] << typer.full(call.result) << call.name
            b << "(" << formatter.argument_list(call.arguments) << ") {\n"
            b << "  static BindgenTypeDiscovery<" << base << "> table {\n"
            @descendants.each_with_index(1) do |node, id|
              name = node.origin.name
              b << "    {BINDGEN_TYPEID(" << name << "), " << id << ", [](" << base
              b << " *p) -> void * { return bindgen_dynamic_cast<" << name << " *>(p); }},\n"
            end
            b << "  };\n"
            b << "  return table.discover(" << self_var << ", " << id_var << ", " << crystal_var << ");\n"
            b << "}\n\n"
          end
        end
      end

      # Crystal body of the `Graph::Class::DISCOVER_METHOD` of a class, see
      # `#add_discovery_method`: returns the Crystal object which constructed
      # the object, see `BindgenHelper.crystal_object`, if it is one of the
      # class.  Else, with a binding *fun_name*, calls it and wraps the pointer
      # it returns in the class it numbers, one of *descendants*, or in the
      # class itself.
      class DiscoverCrystalBody < Call::Body
        def initialize(@db : TypeDatabase, @fun_name : String?, @klass : Graph::Class, @descendants : Array(Graph::Class))
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          typer = Crystal::Typename.new(@db)
          pass = Crystal::Pass.new(@db)
          type_name = typer.full(call.result)
          fallback = call.result.apply_conversion("unwrap")

          String.build do |b|
            b << "# Wraps the object at *unwrap*: in the Crystal object which constructed\n"
            b << "# it, or in the wrapper class of its dynamic type, see `#to?`.\n"
            b << "def self." << call.name << "(unwrap : " << binding_pointer(typer, @klass) << ") : "
            b << type_name << "\n"
            if fun_name = @fun_name
              b << "  ptr = Binding." << fun_name << "(unwrap, out bg_class, out bg_crystal)\n"
              b << "  if object = BindgenHelper.as_crystal_object(bg_crystal, " << type_name << ")\n"
              b << "    return object\n"
              b << "  end\n"
              b << "  case bg_class\n"
              @descendants.each_with_index(1) do |node, id|
                result = pass.from_wrapper(node.origin.as_type.never_nil, discover: false)
                b << "  when " << id << " then " << result.apply_conversion(cast(typer, node)) << "\n"
              end
              b << "  else " << fallback << "\n"
              b << "  end\n"
            else
              b << "  BindgenHelper.crystal_object(unwrap, " << type_name << ") || " << fallback << "\n"
            end
            b << "end\n"
          end
        end

        private def binding_pointer(typer, klass) : String
          "#{typer.qualified(*typer.binding(klass.origin.as_type))}*"
        end

        private def cast(typer, klass) : String
          "ptr.as(#{binding_pointer(typer, klass)})"
        end
      end
    end
  end
end
