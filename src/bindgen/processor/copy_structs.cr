module Bindgen
  module Processor
    # Copies all classes into `lib struct`s which have their `copy_structure`
    # set to `true` in the type database.
    #
    # Has to be run before the `CrystalBinding` processor.
    class CopyStructs < Base
      include TypeHelper

      # The storage of bit-fields in a `lib struct`, by the binding type of the
      # bit-field: The unsigned Crystal type, and its C++ type.
      BIT_FIELD_STORAGE = {
        "Bool"            => {"UInt8", "uint8_t"},
        "Int8"            => {"UInt8", "uint8_t"},
        "UInt8"           => {"UInt8", "uint8_t"},
        "Int16"           => {"UInt16", "uint16_t"},
        "UInt16"          => {"UInt16", "uint16_t"},
        "Int32"           => {"UInt32", "uint32_t"},
        "UInt32"          => {"UInt32", "uint32_t"},
        "Int64"           => {"UInt64", "uint64_t"},
        "UInt64"          => {"UInt64", "uint64_t"},
        "LibC::Long"      => {"LibC::ULong", "unsigned long int"},
        "LibC::ULong"     => {"LibC::ULong", "unsigned long int"},
        "LibC::LongLong"  => {"LibC::ULongLong", "unsigned long long int"},
        "LibC::ULongLong" => {"LibC::ULongLong", "unsigned long long int"},
      }

      # Binding types of signed bit-fields.
      SIGNED_BIT_FIELDS = {"Int8", "Int16", "Int32", "Int64", "LibC::Long", "LibC::LongLong"}

      # The signed counterpart of each storage type, to extend the sign of
      # signed bit-fields.
      SIGNED_STORAGE = {
        "UInt8"           => "Int8",
        "UInt16"          => "Int16",
        "UInt32"          => "Int32",
        "UInt64"          => "Int64",
        "LibC::ULong"     => "LibC::Long",
        "LibC::ULongLong" => "LibC::LongLong",
      }

      # The layout of a `lib struct` while its members are added: The end of
      # the last member in bits, if known, and the bit-fields.
      private class Layout
        property end_bits : Int64? = 0_i64

        # Is the last member the storage of bit-fields?
        property? after_bit_fields = false

        getter bit_fields = [] of Graph::Struct::BitField
      end

      # Host of the C++ functions accessing bit-fields, see `#accessor_host`.
      @accessor_host : Graph::PlatformSpecific?

      # The root of the graph, set in `#process`.
      @root : Graph::Container?

      def process(graph : Graph::Node, doc : Parser::Document)
        @root = graph.as(Graph::Container)
        root = graph.by_name(Graph::LIB_BINDING).as(Graph::Library)

        unused_structures = find_unused_structures(doc)

        @db.each do |cpp_name, rules|
          next unless rules.copy_structure? # Only care about copy-able structures

          klass = find_structure(doc, cpp_name)
          graph = rules.graph_node.as(Graph::Class)
          next if graph.structure                    # Already has a structure?
          next if unused_structures.includes?(graph) # Will be inlined?

          # Can't use `Struct | CppUnion`, as compiler turns it to `Container+`
          case structure = copy_structure(klass, root)
          when Graph::Struct, Graph::CppUnion
            graph.structure = structure
          end
        end
      end

      # Finds the class *name* in the *doc*.  If not found, or if no non-static
      # fields have been found, raises.
      private def find_structure(doc, name) : Parser::Class
        klass = doc.classes[name]?

        if klass.nil? # We know about this, right?
          raise "Can't copy structure of unknown class #{name.inspect}"
        end

        if klass.fields.none? { |f| !f.static? } # We can actually copy something
          raise "Can't copy structure of class #{name.inspect}: It has no non-static fields"
        end

        klass
      end

      # Copies the structure of *klass* into the `lib` *root*.
      private def copy_structure(klass, root)
        typename = Crystal::Typename.new(@db)
        name = typename.binding(klass.as_type).first
        fields, layout = fields_to_graph(klass)
        check_class_layout!(klass)

        # Add the struct or union into the graph
        if klass.cpp_union?
          Graph::CppUnion.new(
            name: name,
            fields: fields,
            parent: root,
          )
        else
          structure = Graph::Struct.new(
            name: name,
            fields: fields,
            parent: root,
          )

          structure.bit_fields.concat layout.bit_fields
          structure
        end
      end

      # Makes sure that *klass* itself can be passed by value like a C
      # structure.  Raises if it can't.  Done after checking the fields, as a
      # field which can't be copied makes the class not copyable too.
      private def check_class_layout!(klass)
        reason = if !klass.trivially_copyable?
                   "It isn't trivially copyable"
                 elsif !klass.standard_layout?
                   "It isn't standard-layout"
                 end

        if reason
          raise "Can't copy structure of class #{klass.name.inspect}: #{reason}"
        end
      end

      # Turns *klass*'s non-static fields into a hash of `Call::Result`s we can
      # store in the graph, and the layout with its bit-fields.
      private def fields_to_graph(klass) : {Hash(String, Call::Result), Layout}
        calls = {} of String => Call::Result
        layout = Layout.new
        add_fields_to_graph(klass, klass, calls, layout, 0_i64)

        if (end_bits = layout.end_bits) && end_bits > klass.byte_size * 8
          raise "Can't copy structure of class #{klass.name.inspect}: " \
                "The storage of its last bit-fields exceeds the structure"
        end

        {calls, layout}
      end

      # Helper for `#fields_to_graph`.  Recursively descends into inlinable
      # member types.  The fields of *klass* are at the bit offset *base* in
      # *root_klass*, the copied class.
      private def add_fields_to_graph(root_klass, klass : Parser::Class, calls, layout, base)
        pass = Crystal::Pass.new(@db)
        argument = Crystal::Argument.new(@db)
        fields = klass.fields.reject(&.static?)
        index = 0

        while index < fields.size
          field = fields[index]

          # Consecutive bit-fields share their storage.
          if field.bit_field?
            run = fields[index..].take_while(&.bit_field?)
            add_bit_fields(root_klass, klass, run, calls, layout, base)
            index += run.size
            next
          end

          offset = field.bit_offset.try(&.+ base)
          check_after_bit_fields!(root_klass, field, offset, layout)
          field_klass, inlinable = get_field_type(klass, field)

          if field_klass && inlinable
            add_fields_to_graph(root_klass, field_klass.origin, calls, layout, offset || base)
          else
            result = lib_struct_field(klass, field, pass.to_binding(field))
            var_name = argument.name(field.crystal_name, calls.size)
            calls[var_name] = result
          end

          size = field.bit_size
          layout.end_bits = offset && size && offset + size
          index += 1
        end
      end

      # The unsigned Crystal type and C++ type storing the bit-field *field*.
      private def bit_field_storage(field) : {String, String}?
        BIT_FIELD_STORAGE[Crystal::Pass.new(@db).to_binding(field).type_name]?
      end

      # Raises if the *field* at the bit *offset* shares the storage of the
      # bit-fields before it, as a C++ compiler may put it there.
      private def check_after_bit_fields!(klass, field, offset, layout)
        return unless layout.after_bit_fields?
        layout.after_bit_fields = false

        end_bits = layout.end_bits
        return if offset && end_bits && offset >= end_bits

        raise "Can't copy structure of class #{klass.name.inspect}: " \
              "The field #{field.name.inspect} shares the storage of the bit-fields before it"
      end

      # Adds the storage of the *run* of consecutive bit-fields of *klass* to
      # the *calls*.  Adds the named ones to the bit-fields of the *layout*.
      #
      # The storage is a member for each unit the bit-fields occupy in C++, of
      # the unsigned type as large as their largest type.  This mirrors the
      # layout of the Itanium C++ ABI, which packs bit-fields of smaller types
      # into the unit of a larger one.  Raises if a member before or after the
      # *run* shares its storage, or if a bit-field crosses a unit.
      private def add_bit_fields(root_klass, klass, run, calls, layout, base)
        error = "Can't copy structure of class #{root_klass.name.inspect}"
        raise "#{error}: The bit-field #{run.first.name.inspect} is in a union" if klass.cpp_union?

        run.each do |f|
          next if bit_field_storage(f)
          raise "#{error}: The bit-field #{f.name.inspect} has the unsupported type #{f.full_name}"
        end

        largest = run.max_by { |f| f.bit_size || raise "BUG: Bit-field #{f.name} has no size" }
        storage_type, storage_cpp = bit_field_storage(largest).not_nil!
        unit_bits = largest.bit_size.not_nil!
        offsets = run.map { |f| base + (f.bit_offset || raise "BUG: Bit-field #{f.name} has no offset") }
        placed = run.zip(offsets).reject { |f, _| f.bit_field == 0 }

        if placed.empty?
          raise "#{error}: The zero-width bit-field #{run.first.name.inspect} doesn't follow other bit-fields"
        end

        placed.each do |f, offset|
          if offset // unit_bits != (offset + f.bit_field - 1) // unit_bits
            raise "#{error}: The bit-field #{f.name.inspect} crosses a storage unit"
          end
        end

        # A zero-width bit-field moves the next member to the next unit of its
        # type, so the storage extends to it.
        end_bits = placed.max_of { |f, offset| offset + f.bit_field }
        end_bits = {end_bits, offsets.max}.max
        first_unit = placed.first[1] // unit_bits
        units = (end_bits + unit_bits - 1) // unit_bits - first_unit

        if (previous_end = layout.end_bits).nil? || first_unit * unit_bits < previous_end
          raise "#{error}: The bit-field #{placed.first[0].name.inspect} shares the storage of the member before it"
        end

        storage_names = Array.new(units) do
          index = 0
          while calls.has_key?("_bits#{index}")
            index += 1
          end

          name = "_bits#{index}"

          calls[name] = Call::Result.new(
            type: Parser::Type.builtin_type(storage_cpp),
            type_name: storage_type,
            reference: false,
            pointer: 0,
          )
          name
        end

        placed.each do |f, offset|
          next if f.name.empty?

          unit = offset // unit_bits
          position = offset - unit * unit_bits
          shift = big_endian? ? unit_bits - position - f.bit_field : position
          type_name = Crystal::Pass.new(@db).to_binding(f).type_name
          getter_fun, setter_fun = bit_field_accessors(root_klass, f) if accessors?(root_klass)

          layout.bit_fields << Graph::Struct::BitField.new(
            name: f.crystal_name,
            type_name: type_name,
            storage: storage_names[unit - first_unit],
            storage_type: storage_type,
            unit_bits: unit_bits,
            shift: shift,
            width: f.bit_field,
            signed_type: (SIGNED_STORAGE[storage_type] if SIGNED_BIT_FIELDS.includes?(type_name)),
            bool: type_name == "Bool",
            const: f.const?,
            doc: f.doc,
            getter_fun: getter_fun,
            setter_fun: setter_fun,
          )
        end

        layout.end_bits = (first_unit + units) * unit_bits
        layout.after_bit_fields = true
      end

      # Does this platform store bit-fields from the most significant bit on?
      private def big_endian? : Bool
        Variables.builtin["endian"]? == "big"
      end

      # Are the bit-fields of *klass* accessed through C++?  Raises for an
      # anonymous type, which C++ functions can't name.
      private def accessors?(klass) : Bool
        mode = @db.try_or(klass.name, TypeDatabase::BitFields::Accessors, &.bit_fields)
        return false if mode.inline?

        if klass.anonymous? && @db[klass.name]?.try(&.cpp_type).nil?
          raise "Can't copy structure of class #{klass.name.inspect}: " \
                "Its bit-fields need `bit_fields: Inline`, as it is anonymous"
        end

        true
      end

      # Adds C++ functions getting and setting the bit-field *field* of *klass*,
      # and binds them.  Returns the names of their `lib` functions; there's no
      # setter for a `const` *field*.
      private def bit_field_accessors(klass, field) : {String, String?}
        getter = Parser::Method.new(
          name: field.name,
          class_name: klass.name,
          return_type: field,
          arguments: [] of Parser::Argument,
          type: Parser::Method::Type::MemberGetter,
          const: true,
          binding_name: "#{field.name}_BITFIELD_GET",
        )

        add_bit_field_accessor(klass, getter, InstanceProperties::GetterBody.new)
        return {getter.mangled_name, nil} if field.const?

        setter = Parser::Method.new(
          name: field.name,
          class_name: klass.name,
          return_type: Parser::Type::VOID,
          arguments: [Parser::Argument.new(field.name, field)],
          type: Parser::Method::Type::MemberSetter,
          binding_name: "#{field.name}_BITFIELD_SET",
        )

        add_bit_field_accessor(klass, setter, InstanceProperties::SetterBody.new)
        {getter.mangled_name, setter.mangled_name}
      end

      # Adds the C++ function and the `lib` function of the bit-field accessor
      # *method* of *klass*.
      private def add_bit_field_accessor(klass, method, body)
        node = Graph::Method.new(origin: method, name: method.name, parent: accessor_host)
        target = CallBuilder::CppCall.new(@db).build(method, body: body)
        node.calls[Graph::Platform::Cpp] = CallBuilder::CppWrapper.new(@db).build(method, target)
        node.calls[Graph::Platform::CrystalBinding] =
          CallBuilder::CrystalBinding.new(@db).build(method, klass.as_type)
      end

      # Hosts the C++ functions accessing bit-fields.  These are bound in
      # `lib Binding`, but have no methods in Crystal wrappers.
      private def accessor_host : Graph::PlatformSpecific
        @accessor_host ||= Graph::PlatformSpecific.new(
          platform: Graph::Platforms.flags(Cpp, CrystalBinding),
          parent: @root,
        )
      end

      # Makes sure that the *field* of *klass* has the same layout in C++ as its
      # *result* has in the `lib struct`.  Returns the result to use, raises if
      # there is none.
      #
      # Only built-in types, enumerations, other copied structures and
      # pointers have.  Anything else is either passed as pointer, or as another
      # type than it really is (like `std::string` as `CrystalString`), which
      # is fine for a method argument, but not for a structure member.  A
      # pointer to such a type becomes a `Void` pointer instead.
      private def lib_struct_field(klass, field, result) : Call::Result
        type_name = field.full_name
        binding_pointer = result.pointer + (result.reference ? 1 : 0)
        converted = @db.try_or(field, false) { |rules| converted_type?(field, rules) }

        reason = if field.reference? || field.move?
                   "it is a reference"
                 elsif field.builtin_array_pointer?
                   nil # A pointer to a `StaticArray`.
                 elsif field.pointer_to_c_array?
                   "pointers to C arrays are only supported for complete arrays of built-in types"
                 elsif !converted && binding_pointer == type_pointer_depth(field)
                   nil # Same layout.
                 elsif field.pointer > 0
                   void = Parser::Type.builtin_type("void", pointer: field.pointer)
                   return Crystal::Pass.new(@db).to_binding(void)
                 elsif converted
                   "its type #{type_name} is converted when passed to Crystal"
                 else
                   "its type #{type_name} is neither built-in, an enumeration nor a copied structure"
                 end

        if reason
          raise "Can't copy structure of class #{klass.name.inspect}: " \
                "The field #{field.name.inspect} can't be part of a lib struct, #{reason}"
        end

        result
      end

      # Do the *rules* of *type* pass it as another type to Crystal?
      private def converted_type?(type, rules) : Bool
        # The rules may be those of the type *type* is an alias for.
        cpp_type = rules.cpp_type
        return true if cpp_type && cpp_type != @db.resolve_aliases(type).base_name

        !rules.to_cpp.no_op? || !rules.from_cpp.no_op?
      end

      # Locates classes whose structures aren't needed due to being inlined in a
      # parent structure.  Applies to unnamed structure members of anonymous
      # types.
      private def find_unused_structures(doc : Parser::Document)
        nodes = Set(Graph::Class).new
        nodes.compare_by_identity

        @db.each do |cpp_name, rules|
          next unless rules.copy_structure?

          if klass = doc.classes[cpp_name]?
            klass.fields.each do |field|
              field_klass, inlinable = get_field_type(klass, field)
              nodes << field_klass if field_klass && inlinable
            end
          end
        end

        nodes
      end

      # Looks up the class of the *field* inside the given *klass*.  Returns the
      # graph node, and whether the field's own data members can be inlined.
      private def get_field_type(klass, field) : {Graph::Class?, Bool}
        rules = @db[field.base_name]?
        node = rules.try(&.graph_node).as?(Graph::Class)

        inlinable = case
                    when !field.name.empty?
                      false # named members are never inlined
                    when field.static?
                      false # Static data members are never inlined
                    when !rules.try(&.copy_structure?)
                      false # cannot inline field if its structure isn't copied
                    when !node.try(&.origin.anonymous?)
                      false # named types are never inlined
                    when klass.cpp_union? != node.try(&.origin.cpp_union?)
                      false # a C union cannot be inlined inside a struct, and vice-versa
                    else
                      true
                    end

        {node, inlinable}
      end
    end
  end
end
