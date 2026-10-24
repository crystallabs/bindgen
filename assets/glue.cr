# This file is part of bindgen
#   See: https://github.com/Papierkorb/bindgen
#
# This file is licensed under the following "public domain" license.
# IT APPLIES ONLY TO THIS FILE `bindgen_helper.h` AND NOT TO ANY OTHER FILE.
#
# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <http://unlicense.org/>

# This file will *not* be run by bindgen directly.  Instead, its contents after
# the following marker are copied into the target module.

########## SNIP ##########

# Native bindings.  Mostly generated.
lib Binding
  # Container for string data.
  struct CrystalString
    ptr : LibC::Char*
    size : LibC::Int
  end

  # Container for a `Proc`
  struct CrystalProc
    ptr : Void*
    context : Void*
  end

  # Container for raw memory-data.  The `ptr` could be anything.  `ptr` and
  # `size` lead, as in earlier versions which lacked `read_only`.
  struct CrystalSlice
    ptr : Void*
    size : LibC::Int
    read_only : Bool
  end

  # Container for a C array of wrapped class instances, see
  # `BindgenHelper::ArrayView`.  `assign` copy-assigns the element at its
  # second argument to the one at its first, it's null if the C++ type can't be
  # copy-assigned.
  struct CrystalArray
    ptr : Void*
    size : LibC::Int
    read_only : Bool
    element_size : LibC::Int
    assign : Void*, Void* -> Void
  end

  # Registers a function C++ calls with the address of a wrapped object it
  # destroys.  Defined in `bindgen_helper.hpp`.
  fun bindgen_add_destroyed_hook(hook : Void* -> Void) : Void

  # The key of a wrapped object in `BindgenHelper`'s table of kept objects:
  # the start of its GC allocation, or null for an object C++ created.  Defined
  # in `bindgen_helper.hpp`.
  fun bindgen_kept_key(object : Void*) : Void*

  ########## IF CPP ##########
  # Remembers the Crystal object which constructed the C++ object, and reads
  # it back, see `BindgenHelper.crystal_object`.  Defined in
  # `bindgen_helper.hpp`.
  fun bindgen_set_crystal_object(object : Void*, crystal : Void*) : Void
  fun bindgen_crystal_object(object : Void*) : Void*
  ########## END IF ##########
end

# Marks the generated wrapper classes.  A method of a wrapped class called on
# an instance of a Crystal subclass, which has none, knows that Crystal's
# dispatch ran the overrides of the subclass already, and calls the C++
# implementation of a virtual method through `#superclass`, so `super` works.
# Also marks these methods themselves: the compiler copies them into the
# subclasses, and the constructors must not take a copy for an override.  On a
# class, its argument is the C++ name of the wrapped class, `"QWidget"`, which
# the Qt meta-object macros need for the types of signals and properties.
annotation BindgenWrapper
end

# Helpers for bindings.  Required.
module BindgenHelper
  ########## IF CPP ##########
  # Remembers *crystal*, the Crystal object which constructed the C++ object at
  # *pointer*, in that object, if Crystal allocated it.  The generated
  # constructors call this, and a pointer to the object coming back from C++
  # is wrapped by *crystal* again, see `.crystal_object` and SPEC.md §2.3.7.
  def self.set_crystal_object(pointer : Pointer, crystal : Reference) : Nil
    Binding.bindgen_set_crystal_object(pointer.as(Void*), crystal.as(Void*))
  end

  # The Crystal object which constructed the C++ object at *pointer*, if there
  # is one and it is a *type*, else `nil`.  *pointer* may point into the
  # object, like to a secondary base.
  def self.crystal_object(pointer : Pointer, type : T.class) : T? forall T
    as_crystal_object(Binding.bindgen_crystal_object(pointer.as(Void*)), type)
  end

  # The Crystal object at *object*, a pointer `.crystal_object` read, if it is
  # a *type*, else `nil`: the object may be of another class, like a
  # `Qt::Widget` behind the `QPaintDevice *` of a painter, or of a class of
  # another binding.  A pointer can't be cast to `Reference` for a check, so
  # the type id in the object's header is followed up the superclasses
  # registered by `Wrapper` until it reaches *type*, or a class not registered.
  def self.as_crystal_object(object : Void*, type : T.class) : T? forall T
    return nil if object.null?

    id = object.as(Int32*).value
    until id == T.crystal_instance_type_id
      id = CRYSTAL_SUPERCLASS_IDS[id]? || return nil
    end

    object.as(T)
  end
  ########## END IF ##########

  # The type id of the superclass of every wrapper class and every Crystal
  # subclass of one, by the type id of the class, see `Wrapper`.
  CRYSTAL_SUPERCLASS_IDS = {} of Int32 => Int32

  # Registers *klass*, with its *superclass*, for `.as_crystal_object`.
  def self.register_class(klass : T.class, superclass : S.class) : Nil forall T, S
    CRYSTAL_SUPERCLASS_IDS[T.crystal_instance_type_id] = S.crystal_instance_type_id
  end

  # Included by the generated wrapper classes: registers the class and, as
  # it is defined, every Crystal subclass of it for `.as_crystal_object`,
  # which so needs no name of a subclass, like of a `private class`.
  module Wrapper
    macro included
      BindgenHelper.register_class(self, {{ @type.superclass }})

      # Reaches `BindgenHelper` from a subclass defined outside its module.
      def self.bindgen_register_class(superclass : S.class) : Nil forall S
        BindgenHelper.register_class(self, superclass)
      end

      macro inherited
        bindgen_register_class(\{{ @type.superclass }})
      end
    end
  end

  # Wraps `Proc` to a `Binding::CrystalProc`, which can then passed on to C++.
  def self.wrap_proc(proc : Proc)
    Binding::CrystalProc.new(
      ptr: proc.pointer,
      context: proc.closure_data,
    )
  end

  # Wraps `Proc` to a `Binding::CrystalProc`, which can then passed on to C++.
  # `Nil` version, returns a null-proc.
  def self.wrap_proc(nothing : Nil)
    Binding::CrystalProc.new(
      ptr: Pointer(Void).null,
      context: Pointer(Void).null,
    )
  end

  # Wraps `String` to a `Binding::CrystalString`, which can then be passed on to
  # C++.  The result points into *string*, it doesn't copy it.
  def self.wrap_string(string : String) : Binding::CrystalString
    Binding::CrystalString.new(
      ptr: string.to_unsafe,
      size: string.bytesize,
    )
  end

  # Unwraps a `Binding::CrystalString` to a `String`, copying its bytes.
  def self.unwrap_string(string : Binding::CrystalString) : String
    String.new(string.ptr, string.size)
  end

  # The handler of an exception raised by a callback from C++: a Crystal
  # override of a virtual method, or the block of a signal.  The callback
  # returns a zero to C++ instead, see `.rescued`.  By default, prints the
  # exception and its backtrace to the standard error.
  @@on_exception : ::Proc(::Exception, ::Nil) = ->(exception : ::Exception) {
    ::STDERR.puts "Unhandled exception in a callback from C++:"
    exception.inspect_with_backtrace(::STDERR)
  }

  def self.on_exception : ::Proc(::Exception, ::Nil)
    @@on_exception
  end

  def self.on_exception=(handler : ::Proc(::Exception, ::Nil))
    @@on_exception = handler
  end

  # Runs the block, a callback from C++.  If it raises, hands the exception to
  # `.on_exception` and returns *fallback*, a zero of the result type: a
  # Crystal exception can't unwind through the C++ frames of the caller.
  def self.rescued(fallback, &)
    yield
  rescue exception : ::Exception
    @@on_exception.call(exception)
    fallback
  end

  # A zero of *type*: `nil`, `false`, `0`, the enum of `0`, a null pointer or a
  # zeroed `lib` structure.  `.rescued` returns it to C++.
  macro zero_value(type)
    {% t = type.resolve %}
    {% if t == ::Nil %}
      nil
    {% elsif t == ::Bool %}
      false
    {% elsif t < ::Number %}
      {{ type }}.zero
    {% elsif t < ::Enum %}
      {{ type }}.new(0)
    {% elsif t < ::Pointer %}
      {{ type }}.null
    {% else %}
      {{ type }}.new
    {% end %}
  end

  # Why an object is kept alive: passed to `.keep_alive`, given an owner by
  # `.owned_by`, or both.  It's collectable again once neither holds: `.release`
  # ends both, `.owned_by` with `nil` the owner's only.
  @[Flags]
  enum KeptBy
    KeepAlive
    Owner
  end

  # Objects kept alive, by the key of their C++ object, see `.kept_key`: the
  # wrapper, and why it's kept.  Getters return a new wrapper each time, so any
  # wrapper of the C++ object finds it.  The GC scans the pointers stored in
  # the hash.
  @@kept_alive = {} of UInt64 => {Void*, KeptBy}

  # Guards `@@kept_alive`.  Reentrant, as a GC finalizer may run C++ code
  # releasing an object while this fiber changes `@@kept_alive`.
  @@kept_alive_mutex = ::Mutex.new(:reentrant) # A wrapped class may be named `Mutex`

  # Set while `@@kept_alive` changes.  Releases meanwhile are queued in
  # `@@pending_releases` and done afterwards.
  @@kept_alive_busy = false

  # A release queued while `@@kept_alive` was busy: the key, and the reasons to
  # drop.
  record PendingRelease, address : UInt64, by : KeptBy

  # The releases to do once `@@kept_alive` is free again.  In memory of
  # `malloc`, which the GC doesn't manage: a release may run in a GC finalizer,
  # and queueing it must not run more finalizers.  Grown as needed.
  @@pending_releases = Pointer(PendingRelease).null
  @@pending_release_capacity = 0
  @@pending_release_count = 0

  # The key of the C++ object at *pointer* in `@@kept_alive`: the start of its
  # GC allocation with C++ glue, so a wrapper of a secondary base of the object,
  # like `widget.as_paint_device`, and the hook of its destruction find the
  # entry of the object.  `0` for an object C++ created, which Crystal only
  # wraps, off the GC heap or allocated uncollectable by the `operator new` of
  # libgccpp: it isn't kept, as its wrapper keeps nothing C++ uses, and nothing
  # would release it when C++ deletes it.  Without C++ glue the address itself.
  private def self.kept_key(pointer : Pointer) : UInt64
    ########## IF CPP ##########
    pointer = Binding.bindgen_kept_key(pointer.as(Void*))
    ########## END IF ##########
    pointer.address
  end

  # Changes `@@kept_alive` in the block, then does the queued releases.  Call
  # with `@@kept_alive_mutex` locked.
  private def self.change_kept_alive(&)
    @@kept_alive_busy = true
    yield
    while @@pending_release_count > 0
      @@pending_release_count -= 1
      pending = @@pending_releases[@@pending_release_count]
      drop_reasons(pending.address, pending.by)
    end
  ensure
    @@kept_alive_busy = false
  end

  # Queues the release of *address* until `@@kept_alive` is free again.  Call
  # with `@@kept_alive_mutex` locked.
  private def self.queue_release(address : UInt64, by : KeptBy) : Nil
    if @@pending_release_count == @@pending_release_capacity
      capacity = Math.max(64, @@pending_release_capacity * 2)
      buffer = LibC.realloc(@@pending_releases.as(Void*), LibC::SizeT.new(capacity * sizeof(PendingRelease)))
      return if buffer.null? # Out of memory: the object stays kept alive, which is safe
      @@pending_releases = buffer.as(PendingRelease*)
      @@pending_release_capacity = capacity
    end
    @@pending_releases[@@pending_release_count] = PendingRelease.new(address, by)
    @@pending_release_count += 1
  end

  # Keeps *object* alive for the reason *by*, adding it to the reasons it's
  # kept for.  An object C++ created isn't kept, see `.kept_key`.  If its
  # C++ object is kept alive already, the wrapper kept first stays.
  private def self.add_reason(object : Reference, by : KeptBy) : Nil
    address = kept_key(object.to_unsafe)
    return if address == 0

    @@kept_alive_mutex.synchronize do
      change_kept_alive do
        if entry = @@kept_alive[address]?
          @@kept_alive[address] = {entry[0], entry[1] | by}
        else
          @@kept_alive[address] = {object.as(Void*), by}
        end
      end
    end
  end

  # Drops the reasons *by* the object with the key *address* is kept for,
  # letting the GC collect it once none is left.  Call with
  # `@@kept_alive_mutex` locked and `@@kept_alive` busy.
  private def self.drop_reasons(address : UInt64, by : KeptBy) : Nil
    return unless entry = @@kept_alive[address]?

    left = entry[1] & ~by
    if left.none?
      @@kept_alive.delete(address)
    else
      @@kept_alive[address] = {entry[0], left}
    end
  end

  # Drops the reasons *by* the object at *pointer* is kept for, queueing the
  # release while `@@kept_alive` is busy.
  private def self.remove_reason(pointer : Pointer, by : KeptBy) : Nil
    address = kept_key(pointer)
    return if address == 0

    @@kept_alive_mutex.synchronize do
      if @@kept_alive_busy
        queue_release(address, by)
      else
        change_kept_alive { drop_reasons(address, by) }
      end
    end
  end

  # Keeps *object* alive until it's passed to `.release`, or C++ deletes it, if
  # it was constructed from Crystal.  Wrapper methods call this on arguments of
  # methods configured in `keep_alive:`, as C++ keeps a pointer to them in
  # memory the GC doesn't scan.  The wrapper references the C++ object, so
  # neither is collected.  An object C++ created, which Crystal only wraps,
  # isn't kept: its wrapper keeps nothing C++ uses.  If its C++ object is kept
  # alive already, the wrapper kept first stays.  Returns *object*.
  def self.keep_alive(object : Reference)
    add_reason(object, :keep_alive)
    object
  end

  # `Nil` version, does nothing.
  def self.keep_alive(nothing : Nil) : Nil
  end

  # Keeps *object* alive while it has an *owner*, which deletes it, like a Qt
  # parent: the `Qt` processor calls this from the constructors and setters
  # giving an object a parent.  Given no owner, `nil`, the object is collectable
  # again, unless `.keep_alive` keeps it, like a model set on a view: having an
  # owner is a reason of its own, and a new owner replaces the former.  `.release`
  # and C++ deleting the object end both.  Returns *object*.
  def self.owned_by(object : Reference, owner : Reference)
    add_reason(object, :owner)
    object
  end

  # `Nil` owner: Lets the GC collect *object* again, unless `.keep_alive` keeps
  # it.  Returns *object*.
  def self.owned_by(object : Reference, owner : Nil)
    remove_reason(object.to_unsafe, :owner)
    object
  end

  # Lets the GC collect *object* again, once it's no longer referenced, also if
  # it was given an owner by `.owned_by`: a method handing an object back, like
  # `QTreeWidget::takeTopLevelItem`, ends its ownership.  Call this when C++ no
  # longer uses the object passed to `.keep_alive`, but didn't delete it: C++
  # deleting an object constructed from Crystal releases it.  Any wrapper of the
  # same C++ object releases it.  Returns *object*.
  def self.release(object : Reference)
    remove_reason(object.to_unsafe, :all)
    object
  end

  # `Nil` version, does nothing.
  def self.release(nothing : Nil) : Nil
  end

  # Releases the C++ object at *pointer*, like `.release(object)`.  For code
  # which only has the pointer: C++ calls this as it destroys a wrapped object,
  # which may happen in a GC finalizer.
  def self.release(pointer : Pointer) : Nil
    remove_reason(pointer, :all)
  end

  # Returns if *object*, or another wrapper of its C++ object, is kept alive by
  # `.keep_alive` or `.owned_by`.
  def self.kept_alive?(object : Reference) : Bool
    @@kept_alive_mutex.synchronize { @@kept_alive.has_key?(kept_key(object.to_unsafe)) }
  end

  ########## IF CPP ##########
  # C++ releases the objects it destroys: `CrystalGCCleanupWrapper` in
  # `bindgen_helper.hpp` calls the hook from its destructor, so an object its
  # owner deleted, like the child of a Qt parent, doesn't stay kept alive.  Not
  # a closure, as C++ calls it without a context.  Only with C++ glue, which
  # defines the hook list; a C library has neither.
  Binding.bindgen_add_destroyed_hook(->(pointer : Void*) { BindgenHelper.release(pointer) })

  ########## END IF ##########

  # Yields *value*.  Used by conversion templates using `%` more than once, so
  # that the expression is evaluated only once.
  def self.evaluate_once(value, &)
    yield value
  end

  # Wraps `Slice` to a `Binding::CrystalSlice`, which can then pass on to C++.
  def self.wrap_slice(slice : Slice(T)) forall T
    Binding::CrystalSlice.new(
      ptr: slice.to_unsafe.as(Pointer(Void)),
      size: slice.size,
      read_only: slice.read_only?,
    )
  end

  # Wraps `Slice` to a `Binding::CrystalSlice`, which can then pass on to C++.
  # `Nil` version, returns an empty slice.
  def self.wrap_slice(nothing : Nil)
    Binding::CrystalSlice.new(
      ptr: Pointer(Void).null,
      size: 0,
      read_only: true,
    )
  end

  # Passes *slice* as reference to a C array of the *array* type.  Raises an
  # `ArgumentError` unless the sizes match.
  def self.slice_to_array(slice : Slice(T), array : StaticArray(T, N).class) : Pointer(StaticArray(T, N)) forall T, N
    unless slice.size == N
      raise ArgumentError.new("Expected a Slice of #{N} elements, got #{slice.size}")
    end

    slice.to_unsafe.as(Pointer(StaticArray(T, N)))
  end

  # Unwraps a `Binding::CrystalSlice` to a Crystal `Slice(T)`.
  module SliceConverter(T)
    def self.unwrap(slice : Binding::CrystalSlice)
      Slice(T).new(slice.ptr.as(Pointer(T)), slice.size, read_only: slice.read_only)
    end
  end

  # Passes the *view* as reference to a C array of *size* elements.  Raises an
  # `ArgumentError` unless the sizes match.
  def self.view_to_array(view : ArrayView(T), size : Int32) : Pointer(Void) forall T
    unless view.size == size
      raise ArgumentError.new("Expected an ArrayView of #{size} elements, got #{view.size}")
    end

    view.to_unsafe
  end

  # `Indexable` view of a C array of wrapped class instances `T`, like an array
  # member of a wrapped class.  The view and its elements refer to the C++
  # array, they don't copy it: changes to an element are visible in C++.
  #
  # Elements are assigned through their C++ copy-assignment operator.  This
  # raises if the array is `const`, or the class can't be copy-assigned.
  struct ArrayView(T)
    include Indexable(T)

    def initialize(@array : Binding::CrystalArray)
    end

    def size : Int32
      @array.size
    end

    # Returns if the C array is `const`.
    def read_only? : Bool
      @array.read_only
    end

    # Returns a wrapper of the element at *index*, referring to the element in
    # the C array.
    def unsafe_fetch(index : Int) : T
      T.new(unwrap: element_pointer(index))
    end

    # Copy-assigns *value* to the element at *index*.
    def []=(index : Int, value : T) : T
      raise "Can't write to read-only ArrayView" if read_only?
      raise "Can't copy-assign elements of #{T}" if @array.assign.pointer.null?

      index = check_index_out_of_bounds(index)
      @array.assign.call(element_pointer(index), value.to_unsafe.as(Void*))
      value
    end

    # Returns a pointer to the first element.
    def to_unsafe : Pointer(Void)
      @array.ptr
    end

    def to_s(io)
      to_a.to_s(io)
    end

    def inspect(io)
      io << "<Wrapped "
      to_a.inspect(io)
      io << ">"
    end

    private def element_pointer(index) : Pointer(Void)
      (@array.ptr.as(UInt8*) + index.to_i64 * @array.element_size).as(Void*)
    end
  end

  # Wraps a *list* into a container *wrapper*, if it's not already one.
  def self.wrap_container(wrapper : T.class, list) : T forall T
    if list.is_a?(T)
      list
    else
      wrapper.new.concat(list)
    end
  end

  # Wrapper for an instantiated, sequential container type.
  #
  # This offers (almost) all read-only methods known from `Array`.
  # Additionally, there's `#<<`.  Other than that, the container type is not
  # meant to be used for storage, but for data transmission between the C++
  # and the Crystal world.  Don't let that discourage you though.
  module SequentialContainer(T)
    include Indexable(T)

    # `#unsafe_at` and `#size` will be implemented by the wrapper class.

    # Implements `Indexable#unsafe_fetch`, which takes any `Int`, through the
    # wrapper's `#unsafe_at`, which takes the C++ index type.
    def unsafe_fetch(index : Int) : T
      unsafe_at(index.to_i32)
    end

    # Adds an element at the end.  Implemented by the wrapper.
    abstract def push(value : T)

    # Adds *element* at the end of the container.
    def <<(value : T) : self
      push(value)
      self
    end

    # Adds all *elements* at the end of the container, retaining their order.
    def concat(values : Enumerable(T)) : self
      values.each { |v| push(v) }
      self
    end

    def to_s(io)
      to_a.to_s(io)
    end

    def inspect(io)
      io << "<Wrapped "
      to_a.inspect(io)
      io << ">"
    end

    # Note: Crystal has no dependent types, so this module must refer to its own
    # type parameter `T`.
    private module ClassMethods(T)
      # Wraps the list of *values* into a container of this type, if it's not
      # already one.
      def from(values : Enumerable(T)) : self
        BindgenHelper.wrap_container(self, values)
      end
    end

    macro included
      extend ClassMethods(T)
    end
  end

  # Wrapper for an instantiated set type, like `std::set` or `QSet`.
  #
  # An `Enumerable` of the elements with `#includes?`, `#<<` and `#delete`, a
  # subset of `Set`.  Like a sequential container, it's meant for data
  # transmission between the C++ and Crystal worlds, not for storage.
  module SetContainer(T)
    include Enumerable(T)

    # `#size`, `#unsafe_count`, `#unsafe_insert` and `#unsafe_erase` will be
    # implemented by the wrapper class.  The wrapper class also has an
    # `Elements` class.

    # Returns if *value* is an element.
    def includes?(value : T) : Bool
      unsafe_count(value) > 0
    end

    # Adds *value*.
    def add(value : T) : self
      unsafe_insert(value)
      self
    end

    # :ditto:
    def <<(value : T) : self
      add(value)
    end

    # Adds all *values*.
    def concat(values : Enumerable(T)) : self
      values.each { |value| add(value) }
      self
    end

    # Removes *value*, returning if it was an element.
    def delete(value : T) : Bool
      return false unless includes?(value)

      unsafe_erase(value)
      true
    end

    def empty? : Bool
      size == 0
    end

    # Yields each element.  The elements are copied beforehand.
    def each(& : T ->) : Nil
      elements = {{ "#{@type}::Elements".id }}.new(self)
      elements.size.times do |i|
        yield elements.unsafe_at(i)
      end
    end

    def to_s(io)
      to_set.to_s(io)
    end

    def inspect(io)
      io << "<Wrapped "
      to_set.inspect(io)
      io << ">"
    end

    # Note: Crystal has no dependent types, so this module must refer to its own
    # type parameter `T`.
    private module ClassMethods(T)
      # Wraps the *values* into a container of this type, if it's not already
      # one.
      def from(values : Enumerable(T)) : self
        BindgenHelper.wrap_container(self, values)
      end
    end

    macro included
      extend ClassMethods(T)
    end
  end

  # Wrapper for an instantiated pair type, like `std::pair` or `QPair`.
  #
  # Pairs convert to and from a `Tuple` of the two values, so wrapped methods
  # take and return tuples; this wrapper is only seen when built directly, by
  # `.from` or `Pair.of(A, B).new`.
  module PairContainer(A, B)
    # `.unsafe_first`, `.unsafe_second` and `.unsafe_set` will be implemented
    # by the wrapper class.

    # The first value.
    def first : A
      self.class.unsafe_first(self)
    end

    # The second value.
    def second : B
      self.class.unsafe_second(self)
    end

    # Sets both values.
    def set(first : A, second : B) : self
      self.class.unsafe_set(self, first, second)
      self
    end

    # Both values as a tuple.
    def to_tuple : {A, B}
      {first, second}
    end

    def to_s(io)
      to_tuple.to_s(io)
    end

    def inspect(io)
      io << "<Wrapped "
      to_tuple.inspect(io)
      io << ">"
    end

    # Note: Crystal has no dependent types, so this module must refer to its
    # own type parameters.
    private module ClassMethods(A, B)
      # Wraps the *values* into a pair of this type, if it's not already one.
      def from(values : {A, B}) : self
        new.set(*values)
      end

      # :ditto:
      def from(values : self) : self
        values
      end
    end

    macro included
      extend ClassMethods(A, B)
    end
  end

  # Wrapper for an instantiated optional type, like `std::optional`.
  #
  # Optionals convert to and from a `T?`, the value or `nil`, so wrapped
  # methods take and return those; this wrapper is only seen when built
  # directly, by `.from` or `Optional.of(T).new`.
  module OptionalContainer(T)
    # `#unsafe_has_value`, `#unsafe_value` and `#unsafe_emplace` will be
    # implemented by the wrapper class.

    # Is there a value?
    def has_value? : Bool
      unsafe_has_value
    end

    # The value, or `nil` if there is none.
    def to_nilable : T?
      unsafe_value if unsafe_has_value
    end

    # Sets the value.
    def value=(value : T) : T
      unsafe_emplace(value)
      value
    end

    def to_s(io)
      to_nilable.to_s(io)
    end

    def inspect(io)
      io << "<Wrapped "
      to_nilable.inspect(io)
      io << ">"
    end

    # Note: Crystal has no dependent types, so this module must refer to its
    # own type parameters.
    private module ClassMethods(T)
      # Wraps the *value* into an optional of this type, empty for `nil`, if
      # it's not already one.
      def from(value : T?) : self
        optional = new
        optional.value = value unless value.nil?
        optional
      end

      # :ditto:
      def from(value : self) : self
        value
      end
    end

    macro included
      extend ClassMethods(T)
    end
  end

  # Wrapper for an instantiated, associative container type.
  #
  # This offers a subset of the methods known from `Hash`, and is `Enumerable`
  # over tuples of the key and the value, like `Hash`.
  #
  # Iteration works on a copy of all entries, which is taken by `#each`.  This
  # makes it safe to change the container while iterating over it.
  module AssociativeContainer(K, V)
    include Enumerable({K, V})

    # `#size`, `#unsafe_count`, `#unsafe_erase` and `#unsafe_store` (or
    # `.unsafe_store`), and `.unsafe_fetch` will be implemented by the wrapper
    # class.  The wrapper class also has an `Entries` class.

    # Returns the value of *key*.  Raises `KeyError` if there's none.
    def [](key : K) : V
      raise KeyError.new("Missing key: #{key.inspect}") unless has_key?(key)
      self.class.unsafe_fetch(self, key)
    end

    # Returns the value of *key*, or `nil` if there's none.
    def []?(key : K) : V?
      self.class.unsafe_fetch(self, key) if has_key?(key)
    end

    # Returns the value of *key*, or *default* if there's none.
    def fetch(key : K, default)
      has_key?(key) ? self.class.unsafe_fetch(self, key) : default
    end

    # Returns the value of *key*, or the value of the block if there's none.
    def fetch(key : K, &)
      has_key?(key) ? self.class.unsafe_fetch(self, key) : yield key
    end

    # Sets the *value* of *key*, replacing an existing value.
    def []=(key : K, value : V) : V
      {% if @type.has_method?(:unsafe_store) %}
        unsafe_store(key, value)
      {% else %}
        self.class.unsafe_store(self, key, value)
      {% end %}
      value
    end

    # Returns if there's a value for *key*.
    def has_key?(key : K) : Bool
      unsafe_count(key) > 0
    end

    # Removes *key*, returning its value, or `nil` if there was none.
    def delete(key : K) : V?
      delete(key) { nil }
    end

    # Removes *key*, returning its value, or the value of the block if there
    # was none.
    def delete(key : K, &)
      return yield key unless has_key?(key)

      value = self.class.unsafe_fetch(self, key)
      unsafe_erase(key)
      value
    end

    def empty? : Bool
      size == 0
    end

    # Yields each key and value.  The entries are copied beforehand.
    def each(& : {K, V} ->) : Nil
      entries = {{ "#{@type}::Entries".id }}.new(self)
      entries.size.times do |i|
        yield({entries.unsafe_key(i), entries.unsafe_value(i)})
      end
    end

    # Yields each key.
    def each_key(& : K ->) : Nil
      each { |key, _| yield key }
    end

    # Yields each value.
    def each_value(& : V ->) : Nil
      each { |_, value| yield value }
    end

    # Returns all keys.
    def keys : Array(K)
      map { |key, _| key }
    end

    # Returns all values.
    def values : Array(V)
      map { |_, value| value }
    end

    # Sets the values of all *pairs*, which may be a `Hash`.
    def concat(pairs : Enumerable({K, V})) : self
      pairs.each { |key, value| self[key] = value }
      self
    end

    # :ditto:
    def merge!(pairs : Enumerable({K, V})) : self
      concat(pairs)
    end

    def to_s(io)
      to_h.to_s(io)
    end

    def inspect(io)
      io << "<Wrapped "
      to_h.inspect(io)
      io << ">"
    end

    # Note: Crystal has no dependent types, so this module must refer to its own
    # type parameters `K` and `V`.
    private module ClassMethods(K, V)
      # Wraps the *pairs*, which may be a `Hash`, into a container of this type,
      # if it's not already one.
      def from(pairs : Enumerable({K, V})) : self
        BindgenHelper.wrap_container(self, pairs)
      end
    end

    macro included
      extend ClassMethods(K, V)
    end
  end
end
