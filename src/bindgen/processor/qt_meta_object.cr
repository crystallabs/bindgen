module Bindgen
  module Processor
    # Meta-objects for Crystal subclasses of `QObject` classes (SPEC.md §Q.4):
    # the signals, slots and properties a Crystal class declares with the
    # `signal`, `@[Qt::Slot]` and `qt_property` macros of the `QObject` wrapper
    # class, which this processor adds from `assets/qt_meta_object.cr`.
    #
    # Runs after `virtual_override`, whose C++ subclass of every class deriving
    # from `QObject` gets a `bgMeta` pointer to a `BindgenQtMetaObject` (see
    # `assets/bindgen_qt_meta.hpp`, which the glue must include), and
    # overrides of `metaObject`, `qt_metacast` and `qt_metacall` using it.
    # The `Qt` processor made those methods non-virtual for the wrappers.  A
    # `SET_META` function, called by a post-hook of the constructors, sets the
    # pointer to the meta-object of the Crystal class, which its `finished`
    # macro built.
    class QtMetaObject < Base
      # The C++ type of a meta-object, of `bindgen_qt_meta.hpp`.
      META_TYPE = "BindgenQtMetaObject"

      # The class whose subclasses get meta-objects.
      QOBJECT = "QObject"

      # Name of the function setting the meta-object of an object.
      SET_META = "SET_META"

      # Name of the field holding it in the C++ subclass.
      META_FIELD = "bgMeta"

      # The Crystal code added, see `#add_glue`.
      GLUE_PATH = "#{__DIR__}/../../../assets/qt_meta_object.cr"

      # Separates the code of the module from the code of the `QObject` class
      # in `GLUE_PATH`.
      CLASS_MARKER = "########## CLASS ##########"

      # The Crystal types `BindgenMeta.cpp_type_name` maps itself.
      BUILTIN_CRYSTAL_TYPES = %w[Int8 Int16 Int32 Int64 UInt8 UInt16 UInt32 UInt64 Float32 Float64 Bool Nil String Bytes Void]

      # Prefix of the conversion functions of a converted value type.
      CONVERTED_PREFIX = "bg_qt_meta"

      # A converted value type: the C++ *name* of the type rules, and its
      # *mangled* name in the conversion functions.
      record Converted, name : String, rules : TypeDatabase::TypeConfig, mangled : String do
        def crystal_type : String
          rules.crystal_type.not_nil!
        end

        # The C type the value crosses the boundary as, in C++ and in Crystal.
        def cpp_type : String
          rules.cpp_type || rules.binding_type || name
        end

        def binding_type : String
          rules.binding_type || rules.cpp_type || name
        end
      end

      # The `QObject` class, if subclassable.
      @qobject : Graph::Class?

      def process(graph : Graph::Container, doc : Parser::Document)
        register_meta_type
        super

        if qobject = @qobject
          converted = converted_types
          add_converted_glue(graph, converted)
          add_glue(graph, qobject, converted)
        else
          Log.warn { "No subclassable #{QOBJECT} class: no meta-objects for Crystal subclasses" }
        end
      end

      # The converted value types (SPEC.md §Q.4): the types with `to_cpp` and
      # `from_cpp` templates passed by value, like `QVariant` or `QChar`,
      # whose Crystal type isn't one the glue maps itself.  Of two rules with
      # the same Crystal type, like `std::chrono::seconds` and `milliseconds`,
      # the first wins.
      private def converted_types : Array(Converted)
        seen = Set(String).new
        list = [] of Converted
        @db.each do |name, rules|
          next if rules.ignore?
          next if rules.to_cpp.no_op? || rules.from_cpp.no_op?
          next unless crystal = rules.crystal_type
          next unless rules.pass_by.value? || rules.wrapper_pass_by.try(&.value?)
          next if name =~ /[*&<>(]/ || crystal.includes?('(') || crystal.includes?('|')
          next if BUILTIN_CRYSTAL_TYPES.includes?(crystal.lchop("::"))
          next unless seen.add?(crystal)
          list << Converted.new(name, rules, Util.mangle_type_name(name))
        end
        list
      end

      # Adds the C++ conversion functions of the *converted* types: reading
      # a value out of an argument vector slot, assigning one to it, and
      # copying one into GC memory for a signal argument.
      private def add_converted_glue(graph : Graph::Container, converted : Array(Converted))
        return if converted.empty?

        code = String.build do |b|
          b << "// Meta-object conversions of the converted value types, see BindgenMeta of the Crystal glue.\n"
          converted.each do |c|
            value = "(*static_cast<const #{c.name} *>(bg_slot))"
            b << "extern \"C\" #{c.cpp_type} #{CONVERTED_PREFIX}_from_#{c.mangled}(void *bg_slot) {\n"
            b << "  return #{c.rules.from_cpp.template(value)};\n"
            b << "}\n"
            b << "extern \"C\" void #{CONVERTED_PREFIX}_to_#{c.mangled}(void *bg_slot, #{c.cpp_type} bg_value) {\n"
            b << "  *static_cast<#{c.name} *>(bg_slot) = #{c.rules.to_cpp.template("bg_value")};\n"
            b << "}\n"
            b << "extern \"C\" void *#{CONVERTED_PREFIX}_pack_#{c.mangled}(#{c.cpp_type} bg_value) {\n"
            b << "  return new (UseGC, bindgen_gc_finalizer<#{c.name}>()) #{c.name}(#{c.rules.to_cpp.template("bg_value")});\n"
            b << "}\n"
          end
        end

        add_cpp_code(graph, "bg_qt_meta_converted", code)
      end

      # The `fun` declarations of the conversion functions.
      private def converted_funs(converted : Array(Converted)) : String
        String.build do |b|
          converted.each do |c|
            b << "  fun #{CONVERTED_PREFIX}_from_#{c.mangled}(slot : Void*) : #{c.binding_type}\n"
            b << "  fun #{CONVERTED_PREFIX}_to_#{c.mangled}(slot : Void*, value : #{c.binding_type}) : Void\n"
            b << "  fun #{CONVERTED_PREFIX}_pack_#{c.mangled}(value : #{c.binding_type}) : Void*\n"
          end
        end
      end

      # The macro condition matching the Crystal type of *c* by name: the
      # type's full name is the one of the rules, in the module or at the
      # top level (`Qt::Variant` or `Variant`), as the rules are written from
      # inside the module.
      private def converted_condition(c : Converted, var : String) : String
        crystal = c.crystal_type
        if crystal.starts_with?("::")
          %[#{var}.name.stringify == #{crystal.lchop("::").inspect}]
        else
          %[(#{var}.name.stringify == #{"#{@config.module}::#{crystal}".inspect} || #{var}.name.stringify == #{crystal.inspect})]
        end
      end

      # The `cpp_type_name` branches of the *converted* types.
      private def converted_names(converted : Array(Converted)) : String
        String.build do |b|
          converted.each do |c|
            b << "    {% elsif #{converted_condition(c, "t")} %}#{c.name.inspect}\n"
          end
        end
      end

      # The `arg` branches: the value read out of the slot, converted.
      private def converted_args(converted : Array(Converted)) : String
        String.build do |b|
          converted.each do |c|
            b << "    {% elsif #{converted_condition(c, "T")} %}\n"
            b << "      #{c.rules.to_crystal.template("::#{@config.module}::Binding.#{CONVERTED_PREFIX}_from_#{c.mangled}(slot)")}\n"
          end
        end
      end

      # The `result` branches: the value assigned to the slot.
      private def converted_results(converted : Array(Converted)) : String
        String.build do |b|
          converted.each do |c|
            b << "    {% elsif #{converted_condition(c, "T")} %}\n"
            b << "      ::#{@config.module}::Binding.#{CONVERTED_PREFIX}_to_#{c.mangled}(slot, #{c.rules.from_crystal.template("value")})\n"
          end
        end
      end

      # The `signal` branches: the argument copied into GC memory.
      private def converted_signal_args(converted : Array(Converted)) : String
        String.build do |b|
          converted.each do |c|
            b << "            {% elsif #{converted_condition(c, "t")} %}\n"
            b << "              bg_args[{{ i }}] = ::#{@config.module}::Binding::BindgenQtArg.new(kind: 0, pointer: ::#{@config.module}::Binding.#{CONVERTED_PREFIX}_pack_#{c.mangled}(#{c.rules.from_crystal.template("{{ a.var }}")}))\n"
          end
        end
      end

      def visit_class(klass)
        return super if klass.wrapped_class # Don't change `Impl` classes.

        if (subclass_name = klass.cpp_sub_class) && derives_from_qobject?(klass.origin.name) && (structure = find_subclass(klass, subclass_name))
          Log.trace { "adding the meta-object to #{klass.diagnostics_path}" }
          @qobject = klass if klass.origin.name == QOBJECT

          add_meta_field(structure)
          add_overrides(structure, klass.origin.name)
          setter = add_set_meta_method(klass, structure, klass.origin.name)
          hook_initializers(klass, setter)
        end

        super
      end

      # Registers `BindgenQtMetaObject`, exchanged as a `Void*`.
      private def register_meta_type
        rules = @db.get_or_add(META_TYPE)
        rules.binding_type = "Void"
        rules.crystal_type = "Void"
        rules.cpp_type = META_TYPE
        rules.kind = Parser::Type::Kind::Struct
        rules.builtin = true
        rules.generate_wrapper = false
        rules.generate_binding = false
      end

      # Does the class *name* derive from `QObject`?
      private def derives_from_qobject?(name : String) : Bool
        return true if name == QOBJECT
        klass = @doc.try(&.classes[name]?)
        return false unless klass
        klass.bases.any? { |base| derives_from_qobject?(base.name) }
      end

      # The `BgInherit_X` structure of *klass*, which `VirtualOverride` put into
      # a C++ platform-specific node.
      private def find_subclass(klass : Graph::Class, name : String) : Graph::Struct?
        klass.nodes.each do |node|
          next unless node.is_a?(Graph::PlatformSpecific)
          node.nodes.each do |inner|
            return inner if inner.is_a?(Graph::Struct) && inner.name == name
          end
        end
        nil
      end

      # Adds `BindgenQtMetaObject *bgMeta = nullptr;` to *structure*.
      private def add_meta_field(structure : Graph::Struct)
        structure.fields[META_FIELD] = Call::Result.new(
          type: Parser::Type.parse(META_TYPE, 1),
          type_name: "#{META_TYPE} *",
          reference: false,
          pointer: 0,
        )
        structure.field_defaults[META_FIELD] = "nullptr"
      end

      # Adds the overrides of the `Q_OBJECT` methods to *structure*, the
      # subclass of the C++ class *base*.
      private def add_overrides(structure : Graph::Struct, base : String)
        add_cpp_method(structure, "metaObject", <<-CPP)
          const QMetaObject *metaObject() const override {
            return #{META_FIELD} ? #{META_FIELD}->metaObject() : #{base}::metaObject();
          }
          CPP
        add_cpp_method(structure, "qt_metacast", <<-CPP)
          void *qt_metacast(const char *bg_name) override {
            if (#{META_FIELD} && bg_name && #{META_FIELD}->isClassName(bg_name)) return static_cast<void *>(this);
            return #{base}::qt_metacast(bg_name);
          }
          CPP
        add_cpp_method(structure, "qt_metacall", <<-CPP)
          int qt_metacall(QMetaObject::Call bg_call, int bg_id, void **bg_argv) override {
            bg_id = #{base}::qt_metacall(bg_call, bg_id, bg_argv);
            if (bg_id < 0 || !#{META_FIELD}) return bg_id;
            return #{META_FIELD}->metacall(this, bindgen_crystal_object(static_cast<#{base} *>(this)), bg_call, bg_id, bg_argv);
          }
          CPP
      end

      # Adds a C++ method written out as *code* to *structure*.
      private def add_cpp_method(structure : Graph::Struct, name : String, code : String)
        origin = Parser::Method.build(
          name: name,
          class_name: structure.name,
          return_type: Parser::Type::VOID,
          arguments: [] of Parser::Argument,
        )
        method = Graph::Method.new(origin: origin, name: name, parent: structure)
        method.calls[Graph::Platform::Cpp] = Call.new(
          origin: origin,
          name: name,
          result: Call::Result.new(type: Parser::Type::VOID, type_name: "void", reference: false, pointer: 0),
          arguments: [] of Call::Argument,
          body: Qt::CodeBody.new(code),
        )
      end

      # Adds the `SET_META` function of *structure*, the subclass of *base*,
      # with its binding, to *klass*.  Returns the method.
      private def add_set_meta_method(klass : Graph::Class, structure : Graph::Struct, base : String) : Parser::Method
        method = Parser::Method.build(
          name: SET_META,
          return_type: Parser::Type::VOID,
          arguments: [Parser::Argument.new("meta", Parser::Type.parse(META_TYPE, 1))],
          class_name: structure.name,
        )

        platforms = Graph::Platforms.flags(CrystalBinding, Cpp)
        graph = Graph::Method.new(origin: method, name: method.name, parent: klass.platform_specific(platforms))

        wrapper = CallBuilder::CppWrapper.new(@db)
        target = CallBuilder::CppCall.new(@db)
        graph.calls[Graph::Platform::Cpp] = wrapper.build(method, target.build(method, body: SetMetaBody.new(base)))
        method
      end

      # Body of `SET_META`: sets the field and the superdata, if the
      # meta-object is one.
      class SetMetaBody < Call::Body
        def initialize(@base : String)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          meta = call.arguments.first.call
          %[if (#{meta}) { _self_->#{META_FIELD} = (#{meta}); _self_->#{META_FIELD}->setSuperdata(&#{@base}::staticMetaObject); }]
        end
      end

      # Adds the hook calling *setter* to the constructors of *klass*.
      private def hook_initializers(klass : Graph::Class, setter : Parser::Method)
        klass.nodes.each do |node|
          next unless node.is_a?(Graph::Method)
          next unless node.origin.any_constructor?
          next if node.tag?(Graph::Method::UNWRAP_INITIALIZE_TAG)

          body = node.calls[Graph::Platform::Crystal]?.try(&.body)
          next unless body.is_a?(Call::HookableBody)
          next if body.post_hook?(SetMetaHook)
          body.add_post_hook(SetMetaHook.new(setter))
        end
      end

      # Post-hook of a constructor: passes the meta-object of the Crystal class,
      # `self.bg_meta_object` of the glue, null for a class without meta
      # members, to `SET_META`.
      class SetMetaHook < Call::Body
        def initialize(@setter : Parser::Method)
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          "Binding.#{@setter.mangled_name}(result, self.class.bg_meta_object)"
        end
      end

      # Adds the Crystal code of `GLUE_PATH`: the module part to the root of
      # *graph*, the class part to the *qobject* class.
      private def add_glue(graph : Graph::Container, qobject : Graph::Class, converted : Array(Converted))
        module_code, _, class_code = File.read(GLUE_PATH).partition(CLASS_MARKER)
        raise "#{GLUE_PATH} lacks the #{CLASS_MARKER} line" if class_code.empty?

        add_crystal_code(graph, "bg_qt_meta_module", substitute(module_code, qobject, converted))
        add_crystal_code(qobject, "bg_qt_meta_class", substitute(class_code, qobject, converted))
      end

      # Fills the placeholders of the glue *code* in.
      private def substitute(code : String, qobject : Graph::Class, converted : Array(Converted)) : String
        connection = @db[Qt::CONNECTION_HANDLE_TYPE]? || raise "The Qt meta-object glue needs type rules for #{Qt::CONNECTION_HANDLE_TYPE}"
        connection_type = @db[Qt::CONNECTION_TYPE]? || raise "The Qt meta-object glue needs the #{Qt::CONNECTION_TYPE} enum wrapped"

        code
          .gsub("%CONVERTED_FUNS%", converted_funs(converted))
          .gsub("%CONVERTED_NAMES%", converted_names(converted))
          .gsub("%CONVERTED_ARGS%", converted_args(converted))
          .gsub("%CONVERTED_RESULTS%", converted_results(converted))
          .gsub("%CONVERTED_SIGNAL_ARGS%", converted_signal_args(converted))
          .gsub("%MODULE%", @config.module)
          .gsub("%OBJECT%", "::#{qobject.path_name}")
          .gsub("%CONNECTION%", connection.crystal_type || raise("#{Qt::CONNECTION_HANDLE_TYPE} has no crystal_type"))
          .gsub("%CONNECTION_BINDING%", connection.binding_type || raise("#{Qt::CONNECTION_HANDLE_TYPE} has no binding_type"))
          .gsub("%CONNECTION_TYPE%", connection_type.crystal_type || raise("#{Qt::CONNECTION_TYPE} has no crystal_type"))
      end

      # Adds *code* as a C++ "method" of *name* to the root of *graph*,
      # written out as given, like `#add_crystal_code`.
      private def add_cpp_code(graph : Graph::Container, name : String, code : String)
        origin = Parser::Method.build(
          name: name,
          class_name: Cpp::MethodName::GLOBAL_SCOPE,
          return_type: Parser::Type::VOID,
          arguments: [] of Parser::Argument,
        )
        method = Graph::Method.new(origin: origin, name: name, parent: graph.platform_specific(Graph::Platform::Cpp))
        method.calls[Graph::Platform::Cpp] = Call.new(
          origin: origin,
          name: name,
          result: Call::Result.new(type: Parser::Type::VOID, type_name: "void", reference: false, pointer: 0),
          arguments: [] of Call::Argument,
          body: Qt::CodeBody.new(code),
        )
      end

      # Adds *code* as a Crystal "method" of *name* to *parent*, written out as
      # given, like `Qt#add_crystal_method`.
      private def add_crystal_code(parent : Graph::Container, name : String, code : String)
        class_name = parent.is_a?(Graph::Class) ? parent.origin.name : ""
        origin = Parser::Method.build(
          name: name,
          class_name: class_name,
          return_type: Parser::Type::VOID,
          arguments: [] of Parser::Argument,
        )
        method = Graph::Method.new(
          origin: origin,
          name: name,
          parent: parent.platform_specific(Graph::Platform::Crystal),
        )
        method.calls[Graph::Platform::Crystal] = Call.new(
          origin: origin,
          name: name,
          result: Call::Result.new(type: Parser::Type::VOID, type_name: "Nil", reference: false, pointer: 0),
          arguments: [] of Call::Argument,
          body: Qt::CodeBody.new(code),
        )
      end
    end
  end
end
