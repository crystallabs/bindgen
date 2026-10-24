# Meta-objects for Crystal subclasses of QObject classes, see SPEC.md §Q.4.
# `Processor::QtMetaObject` writes the part above the marker into the module,
# and the part below it into the QObject wrapper class, filling the
# placeholders in: %MODULE%, %OBJECT%, %CONNECTION%, %CONNECTION_BINDING%,
# %CONNECTION_TYPE%.
lib Binding
  # An argument of a signal emitted from Crystal, see `bindgen_qt_activate`.
  struct BindgenQtArg
    kind : Int32
    pointer : Void*
  end

  fun bindgen_qt_meta_new(class_name : UInt8*) : Void*
  fun bindgen_qt_meta_add_method(meta : Void*, kind : Int32, name : UInt8*, return_type : UInt8*, argc : Int32, types : UInt8**, names : UInt8**) : Int32
  fun bindgen_qt_meta_add_property(meta : Void*, name : UInt8*, type : UInt8*, notify : Int32, writable : Bool, is_enum : Bool) : Int32
  fun bindgen_qt_meta_add_class_info(meta : Void*, key : UInt8*, value : UInt8*) : Int32
  fun bindgen_qt_meta_finish(meta : Void*, parent : Void*, metacall : CrystalProc) : Void
  fun bindgen_qt_signal_index(meta : Void*, local : Int32) : Int32
  fun bindgen_qt_activate(sender : Void*, meta : Void*, local : Int32, args : BindgenQtArg*, count : Int32) : Void
  fun bindgen_qt_connect(sender : Void*, signal_index : Int32, type : Int32, proc : CrystalProc) : %CONNECTION_BINDING%*
  fun bindgen_qt_string_at(slot : Void*) : CrystalString
  fun bindgen_qt_set_string(slot : Void*, string : CrystalString) : Void
  fun bindgen_qt_bytes_at(slot : Void*) : CrystalString
  fun bindgen_qt_set_bytes(slot : Void*, bytes : CrystalString) : Void
  fun bindgen_qt_copy_value(type : UInt8*, source : Void*) : Void*
  fun bindgen_qt_set_value(slot : Void*, type : UInt8*, source : Void*) : Bool
end

# Marks the emission method of a signal declared with `signal`.
annotation Signal
end

# Marks a method as a Qt slot: invokable by name through the meta-object, and
# connectable from C++ and QML.  Its arguments and result need type
# restrictions, of the types `BindgenMeta.cpp_type_name` knows.
annotation Slot
end

# Marks a method as invokable by name through the meta-object, like
# `Q_INVOKABLE`: a slot which isn't one.  Same requirements as `Slot`.
annotation Invokable
end

# Marks the placeholder method of a class info declared with `qt_class_info`.
annotation ClassInfo
end

# Marks the reader of a property declared with `qt_property`.
annotation Property
end

# Conversions between Crystal values and the `void **` argument vectors of
# the meta-object system, for `signal`, `@[Slot]` and `qt_property`.
module BindgenMeta
  # The C++ type name of *type* in the meta-object tables: a string literal.
  macro cpp_type_name(type)
    {% if type.is_a?(Call) && type.name == "|" %}
      {% parts = [type.receiver] + type.args %}
    {% elsif type.is_a?(Union) %}
      {% parts = type.types %}
    {% else %}
      {% parts = [type] %}
    {% end %}
    {% types = [] of Nil %}
    {% for part in parts %}
      {% resolved = part.resolve %}
      {% if resolved.union? %}
        {% for u in resolved.union_types %}{% types << u unless u == Nil %}{% end %}
      {% elsif resolved != Nil || parts.size == 1 %}
        {% types << resolved %}
      {% end %}
    {% end %}
    {% raise "#{type} can't be a signal or property type: only a wrapper class may be nilable" unless types.size == 1 %}
    {% t = types[0] %}
    {% raise "#{type} can't be nilable: only a QObject wrapper class, passed as a pointer, may be" if (parts.size > 1 || parts[0].resolve.union?) && !(t.class? && t <= %OBJECT%) %}
    {% if t == Int32 %}"int"{% elsif t == UInt32 %}"uint"{% elsif t == Int64 %}"qlonglong"{% elsif t == UInt64 %}"qulonglong"
    {% elsif t == Int16 %}"short"{% elsif t == UInt16 %}"ushort"{% elsif t == Int8 %}"signed char"{% elsif t == UInt8 %}"uchar"
    {% elsif t == Float64 %}"double"{% elsif t == Float32 %}"float"{% elsif t == Bool %}"bool"{% elsif t == Nil %}"void"
    {% elsif t == String %}"QString"{% elsif t == Bytes %}"QByteArray"
    {% elsif (ann = t.annotation(::%MODULE%::BindgenWrapper)) && ann.args.size == 1 %}
      {% if t <= %OBJECT% %}{{ ann.args[0] + "*" }}{% else %}{{ ann.args[0] }}{% end %}
    {% else %}
      {% raise "#{type} isn't a type the Qt meta-object system can take: use a number, Bool, String, Bytes, a wrapped Qt class or a wrapped Qt enum" %}
    {% end %}
  end

  # Is *type*, as written in a declaration, a Crystal enum?  A property of an
  # enum type is flagged as such, like `Q_PROPERTY` does, so Qt looks its
  # `QMetaEnum` up (`Qt::Orientation` in the `Qt` namespace, or an enum of the
  # C++ base classes) and writes it from an int or a key name.
  macro enum_type?(type)
    {% if type.is_a?(Union) || (type.is_a?(Call) && type.name == "|") %}
      false
    {% else %}
      {{ type.resolve < ::Enum }}
    {% end %}
  end

  # Wraps the object at the *pointer*, a `void *` slot holding a pointer to
  # an instance of the wrapper class *type*, through its `bg_discover`.
  macro discover(type, pointer)
    {% t = type.resolve %}
    {% method = t.class.methods.find { |m| m.name == "bg_discover" } %}
    {% raise "#{type} isn't a wrapper class" unless method %}
    {{ t }}.bg_discover(({{ pointer }}).as({{ method.args[0].restriction }}))
  end

  # Reads a value of *type* from the argument vector *slot*.
  def self.arg(type : T.class, slot : Void*) : T forall T
    {% if T == String %}
      BindgenHelper.unwrap_string(Binding.bindgen_qt_string_at(slot))
    {% elsif T == Bytes %}
      bytes = Binding.bindgen_qt_bytes_at(slot)
      bytes.size == 0 ? Bytes.empty : Bytes.new(bytes.ptr.as(UInt8*), bytes.size)
    {% elsif T.union? %}
      {% others = T.union_types.reject { |u| u == Nil } %}
      {% raise "#{T} can't be a signal or property type" unless others.size == 1 && others[0] <= %OBJECT% %}
      pointer = slot.as(Void**).value
      pointer.null? ? nil : ::%MODULE%::BindgenMeta.discover({{ others[0] }}, pointer)
    {% elsif T <= %OBJECT% %}
      ::%MODULE%::BindgenMeta.discover({{ T }}, slot.as(Void**).value)
    {% elsif T.struct? && T.annotation(::%MODULE%::BindgenWrapper) %}
      slot.as(T*).value
    {% elsif T.class? && (ann = T.annotation(::%MODULE%::BindgenWrapper)) && ann.args.size == 1 %}
      # A class passed by value: the slot points at a value owned by the caller,
      # so copy it, through its QMetaType, into a GC allocation of our own.
      pointer = Binding.bindgen_qt_copy_value({{ ann.args[0] }}.to_unsafe, slot)
      raise "Qt can't copy a #{ {{ ann.args[0] }} }: the type isn't registered with QMetaType" if pointer.null?
      ::%MODULE%::BindgenMeta.discover({{ T }}, pointer)
    {% else %}
      slot.as(T*).value
    {% end %}
  end

  # Writes *value* into the argument vector *slot*, the result of a slot or a
  # property read, unless the slot is null.
  def self.result(slot : Void*, value : T) : Nil forall T
    return if slot.null?
    {% if T == String %}
      Binding.bindgen_qt_set_string(slot, BindgenHelper.wrap_string(value))
    {% elsif T == Bytes %}
      Binding.bindgen_qt_set_bytes(slot, Binding::CrystalString.new(ptr: value.to_unsafe.as(LibC::Char*), size: value.size))
    {% elsif T == Nil %}
      slot.as(Void**).value = Pointer(Void).null
    {% elsif T.union? %}
      slot.as(Void**).value = value ? value.to_unsafe.as(Void*) : Pointer(Void).null
    {% elsif T <= %OBJECT% %}
      slot.as(Void**).value = value.to_unsafe.as(Void*)
    {% elsif T.class? && (ann = T.annotation(::%MODULE%::BindgenWrapper)) && ann.args.size == 1 %}
      # A class returned by value: the slot points at a value Qt constructed,
      # assigned through its QMetaType.
      unless Binding.bindgen_qt_set_value(slot, {{ ann.args[0] }}.to_unsafe, value.to_unsafe.as(Void*))
        raise "Qt can't copy a #{ {{ ann.args[0] }} }: the type isn't registered with QMetaType"
      end
    {% else %}
      slot.as(T*).value = value
    {% end %}
  end
end

########## CLASS ##########

    # The meta-object of this Crystal class, a `BindgenQtMetaObject`, or null
    # for a class declaring no signals, slots or properties.  Redefined by the
    # `finished` macro of a class declaring some.
    def self.bg_meta_object : Void*
      Pointer(Void).null
    end

    # Declares a Qt signal, `signal value_changed(value : Int32)`: the method
    # `value_changed(value)` emits it, `on_value_changed { |value| }` connects
    # to it, like to a signal of the C++ class.  The argument types are the
    # ones `BindgenMeta.cpp_type_name` knows.
    macro signal(decl)
      {% raise "signal expects a call with typed arguments, like `signal value_changed(value : Int32)`, not #{decl}" unless decl.is_a?(Call) %}
      {% for a in decl.args %}
        {% raise "signal #{decl.name}: the argument #{a} needs a type: `#{a} : Int32`" unless a.is_a?(TypeDeclaration) %}
      {% end %}

      @[::%MODULE%::Signal]
      def {{ decl.name }}({{ decl.args.splat }}) : Nil
        {% if decl.args.empty? %}
          ::%MODULE%::Binding.bindgen_qt_activate(to_unsafe.as(Void*), {{ @type }}.bg_meta_object, BG_SIGNAL_{{ decl.name.upcase }}, Pointer(::%MODULE%::Binding::BindgenQtArg).null, 0)
        {% else %}
          bg_args = uninitialized ::%MODULE%::Binding::BindgenQtArg[{{ decl.args.size }}]
          {% for a, i in decl.args %}
            {% t = a.type.resolve %}
            {% if t.union? %}{% t = t.union_types.reject { |u| u == Nil }.first %}{% end %}
            {% if t == String || t == Bytes %}
              bg_value{{ i }} = {{ a.var }}.nil? ? ::%MODULE%::Binding::CrystalString.new(ptr: Pointer(LibC::Char).null, size: 0) : ::%MODULE%::Binding::CrystalString.new(ptr: {{ a.var }}.not_nil!.to_unsafe.as(LibC::Char*), size: {{ a.var }}.not_nil!.{{ t == String ? "bytesize".id : "size".id }})
              bg_args[{{ i }}] = ::%MODULE%::Binding::BindgenQtArg.new(kind: {{ t == String ? 1 : 2 }}, pointer: pointerof(bg_value{{ i }}).as(Void*))
            {% elsif t <= %OBJECT% %}
              bg_value{{ i }} = {{ a.var }}.try(&.to_unsafe.as(Void*)) || Pointer(Void).null
              bg_args[{{ i }}] = ::%MODULE%::Binding::BindgenQtArg.new(kind: 0, pointer: pointerof(bg_value{{ i }}).as(Void*))
            {% elsif t.class? && t.annotation(::%MODULE%::BindgenWrapper) %}
              bg_args[{{ i }}] = ::%MODULE%::Binding::BindgenQtArg.new(kind: 0, pointer: {{ a.var }}.to_unsafe.as(Void*))
            {% else %}
              bg_value{{ i }} = {{ a.var }}
              bg_args[{{ i }}] = ::%MODULE%::Binding::BindgenQtArg.new(kind: 0, pointer: pointerof(bg_value{{ i }}).as(Void*))
            {% end %}
          {% end %}
          ::%MODULE%::Binding.bindgen_qt_activate(to_unsafe.as(Void*), {{ @type }}.bg_meta_object, BG_SIGNAL_{{ decl.name.upcase }}, bg_args.to_unsafe, {{ decl.args.size }})
        {% end %}
      end

      def on_{{ decl.name }}(type : ::%MODULE%::%CONNECTION_TYPE% = ::%MODULE%::%CONNECTION_TYPE%::AutoConnection, &block : {{ decl.args.map(&.type).splat }} -> Nil) : ::%MODULE%::%CONNECTION%
        bg_proc = ::Proc(Void**, Nil).new do |bg_argv|
          ::%MODULE%::BindgenHelper.rescued(nil) do
            block.call({% for a, i in decl.args %}::%MODULE%::BindgenMeta.arg({{ a.type }}, bg_argv[{{ i + 1 }}]), {% end %})
          end
        end
        bg_index = ::%MODULE%::Binding.bindgen_qt_signal_index({{ @type }}.bg_meta_object, BG_SIGNAL_{{ decl.name.upcase }})
        ::%MODULE%::%CONNECTION%.new(unwrap: ::%MODULE%::Binding.bindgen_qt_connect(to_unsafe.as(Void*), bg_index, type.to_i, ::%MODULE%::BindgenHelper.wrap_proc(bg_proc)))
      end
    end

    # Declares a Qt property, `qt_property value : Int32, write: :value=,
    # notify: :value_changed`: read by the method named by `read:`, the
    # property's name by default, written by the one named by `write:`, if
    # any, and notified by the signal named by `notify:`, if any.
    macro qt_property(decl, read = nil, write = nil, notify = nil)
      {% raise "qt_property expects a typed name, like `qt_property value : Int32`, not #{decl}" unless decl.is_a?(TypeDeclaration) %}
      @[::%MODULE%::Property(name: {{ decl.var.stringify }}, write: {{ write }}, notify: {{ notify }})]
      def bg_property_{{ decl.var }} : {{ decl.type }}
        {{ (read || decl.var).id }}
      end
    end

    # Declares a class info, `qt_class_info "QML.Element", "auto"`: a key and
    # a value in the meta-object, like `Q_CLASSINFO`, read through
    # `QMetaObject::classInfo`.
    macro qt_class_info(key, value)
      {% raise "qt_class_info expects two string literals, like `qt_class_info \"Author\", \"Me\"`" unless key.is_a?(StringLiteral) && value.is_a?(StringLiteral) %}
      @[::%MODULE%::ClassInfo(key: {{ key }}, value: {{ value }})]
      def bg_class_info_{{ key.gsub(/[^A-Za-z0-9_]/, "_").id }} : Nil
      end
    end

    # Installs the `finished` macro building the meta-object of a subclass
    # declaring signals, slots, invokable methods, properties or class infos.
    macro inherited
      macro finished
        \{% signals = @type.methods.select(&.annotation(::%MODULE%::Signal)) %}
        \{% slots = @type.methods.select { |m| m.annotation(::%MODULE%::Slot) || m.annotation(::%MODULE%::Invokable) } %}
        \{% properties = @type.methods.select(&.annotation(::%MODULE%::Property)) %}
        \{% class_infos = @type.methods.select(&.annotation(::%MODULE%::ClassInfo)) %}
        \{% unless signals.empty? && slots.empty? && properties.empty? && class_infos.empty? %}
          \{% for m, i in signals %}
            BG_SIGNAL_\{{ m.name.upcase }} = \{{ i }}
          \{% end %}

          @@bg_meta_object = Pointer(Void).null

          # The meta-object of this class, built on first use.
          def self.bg_meta_object : Void*
            return @@bg_meta_object unless @@bg_meta_object.null?

            meta = ::%MODULE%::Binding.bindgen_qt_meta_new(\{{ @type.name.stringify.split("::").last }}.to_unsafe)
            \{% for m in class_infos %}
              \{% ann = m.annotation(::%MODULE%::ClassInfo) %}
              ::%MODULE%::Binding.bindgen_qt_meta_add_class_info(meta, \{{ ann[:key] }}.to_unsafe, \{{ ann[:value] }}.to_unsafe)
            \{% end %}
            \{% for m, i in signals + slots %}
              \{% raise "#{@type}##{m.name} can't be a Qt slot: its name must be a plain identifier" if m.name.stringify =~ /[?!=]/ %}
              \{% for a in m.args %}
                \{% raise "#{@type}##{m.name}: the argument #{a.name} needs a type restriction to be a Qt slot" if a.restriction.is_a?(Nop) %}
              \{% end %}
              \{% if m.args.empty? %}
                bg_types\{{ i }} = Pointer(UInt8*).null
                bg_names\{{ i }} = Pointer(UInt8*).null
              \{% else %}
                bg_types\{{ i }} = StaticArray[\{% for a in m.args %}::%MODULE%::BindgenMeta.cpp_type_name(\{{ a.restriction }}).to_unsafe, \{% end %}].to_unsafe
                bg_names\{{ i }} = StaticArray[\{% for a in m.args %}\{{ a.name.stringify }}.to_unsafe, \{% end %}].to_unsafe
              \{% end %}
              \{% rt = m.return_type %}
              \{% if i < signals.size %}
                \{% raise "signal #{m.name} must return Nil" if !rt.is_a?(Nop) && rt.resolve != Nil %}
              \{% end %}
              ::%MODULE%::Binding.bindgen_qt_meta_add_method(meta, \{{ i < signals.size ? 0 : (m.annotation(::%MODULE%::Slot) ? 1 : 2) }}, \{{ m.name.stringify.camelcase(lower: true) }}.to_unsafe,
                \{% if rt.is_a?(Nop) %}"void"\{% else %}::%MODULE%::BindgenMeta.cpp_type_name(\{{ rt }})\{% end %}.to_unsafe,
                \{{ m.args.size }}, bg_types\{{ i }}, bg_names\{{ i }})
            \{% end %}
            \{% for p, i in properties %}
              \{% ann = p.annotation(::%MODULE%::Property) %}
              \{% notify = ann[:notify] %}
              \{% notify_index = nil %}
              \{% if notify %}
                \{% for s, k in signals %}
                  \{% notify_index = k if s.name.stringify == notify.id.stringify %}
                \{% end %}
              \{% end %}
              \{% raise "#{@type}: the property #{ann[:name]} notifies through #{notify}, which isn't a signal of the class" if notify && notify_index.nil? %}
              ::%MODULE%::Binding.bindgen_qt_meta_add_property(meta, \{{ ann[:name].id.stringify.camelcase(lower: true) }}.to_unsafe,
                ::%MODULE%::BindgenMeta.cpp_type_name(\{{ p.return_type }}).to_unsafe, \{{ notify_index.nil? ? -1 : notify_index }}, \{{ ann[:write] ? true : false }},
                ::%MODULE%::BindgenMeta.enum_type?(\{{ p.return_type }}))
            \{% end %}
            ::%MODULE%::Binding.bindgen_qt_meta_finish(meta, \{{ @type.superclass }}.bg_meta_object, ::%MODULE%::BindgenHelper.wrap_proc(->\{{ @type }}.bg_metacall(Void*, Int32, Int32, Void**)))
            @@bg_meta_object = meta
          end

          # The `qt_metacall` of this class's part of the meta-object, see
          # `BindgenQtMetaObject::metacall`: *call* is `QMetaObject::Call`,
          # *id* the index of the slot or property in this class.
          def self.bg_metacall(crystal : Void*, call : Int32, id : Int32, argv : Void**) : Nil
            object = crystal.as(\{{ @type }})
            ::%MODULE%::BindgenHelper.rescued(nil) do
              case call
              when 0 # InvokeMetaMethod: the slots and invokables, after the signals
                case id
                \{% for m, i in slots %}
                when \{{ signals.size + i }}
                  \{% rt = m.return_type %}
                  \{% call_args = m.args.map_with_index { |a, j| "::%MODULE%::BindgenMeta.arg(#{a.restriction}, argv[#{j + 1}])".id } %}
                  \{% if rt.is_a?(Nop) || rt.resolve == Nil %}
                    object.\{{ m.name }}(\{{ call_args.splat }})
                  \{% else %}
                    ::%MODULE%::BindgenMeta.result(argv[0], object.\{{ m.name }}(\{{ call_args.splat }}))
                  \{% end %}
                \{% end %}
                end
              when 1 # ReadProperty
                case id
                \{% for p, i in properties %}
                when \{{ i }} then ::%MODULE%::BindgenMeta.result(argv[0], object.\{{ p.name }})
                \{% end %}
                end
              when 2 # WriteProperty
                case id
                \{% for p, i in properties %}
                  \{% if write = p.annotation(::%MODULE%::Property)[:write] %}
                when \{{ i }} then object.\{{ write.id }}(::%MODULE%::BindgenMeta.arg(\{{ p.return_type }}, argv[0]))
                  \{% end %}
                \{% end %}
                end
              end
              nil
            end
          end
        \{% end %}
      end
    end
