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
end

# Helpers for bindings.  Required.
module BindgenHelper
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

  # Objects kept alive by `.keep_alive`, by the address of their C++ object.
  # Getters return a new wrapper each time, so any wrapper of the C++ object
  # finds it.  The GC scans the pointers stored in the hash.
  @@kept_alive = {} of UInt64 => Void*

  # Guards `@@kept_alive`.  Reentrant, as a GC finalizer may run C++ code
  # releasing an object while this fiber changes `@@kept_alive`.
  @@kept_alive_mutex = Mutex.new(:reentrant)

  # Set while `@@kept_alive` changes.  Releases meanwhile are queued in
  # `@@pending_releases`, which doesn't allocate, and done afterwards.
  @@kept_alive_busy = false
  @@pending_releases = StaticArray(UInt64, 64).new(0_u64)
  @@pending_release_count = 0

  # Changes `@@kept_alive` in the block, then does the queued releases.  Call
  # with `@@kept_alive_mutex` locked.
  private def self.change_kept_alive(&)
    @@kept_alive_busy = true
    yield
    while @@pending_release_count > 0
      @@pending_release_count -= 1
      @@kept_alive.delete(@@pending_releases[@@pending_release_count])
    end
  ensure
    @@kept_alive_busy = false
  end

  # Keeps *object* alive until it's passed to `.release`.  Wrapper methods call
  # this on arguments of methods configured in `keep_alive:`, as C++ keeps a
  # pointer to them in memory the GC doesn't scan.  The wrapper references the
  # C++ object, so neither is collected.  If its C++ object is kept alive
  # already, the wrapper kept first stays.  Returns *object*.
  def self.keep_alive(object : Reference)
    address = object.to_unsafe.address
    @@kept_alive_mutex.synchronize do
      change_kept_alive do
        @@kept_alive[address] = object.as(Void*) unless @@kept_alive.has_key?(address)
      end
    end
    object
  end

  # `Nil` version, does nothing.
  def self.keep_alive(nothing : Nil) : Nil
  end

  # Lets the GC collect *object* again, once it's no longer referenced.  Call
  # this when C++ no longer uses the object passed to `.keep_alive`.  Any
  # wrapper of the same C++ object releases it.  Returns *object*.
  def self.release(object : Reference)
    release(object.to_unsafe)
    object
  end

  # Releases the C++ object at *pointer*, like `.release(object)`.  For code
  # which only has the pointer, like a callback run as C++ destroys an object,
  # which may happen in a GC finalizer.
  def self.release(pointer : Pointer) : Nil
    address = pointer.address
    @@kept_alive_mutex.synchronize do
      if !@@kept_alive_busy
        change_kept_alive { @@kept_alive.delete(address) }
      elsif @@pending_release_count < @@pending_releases.size
        @@pending_releases[@@pending_release_count] = address
        @@pending_release_count += 1
      end # Else the object stays kept alive, which is safe.
    end
  end

  # Returns if *object*, or another wrapper of its C++ object, is kept alive by
  # `.keep_alive`.
  def self.kept_alive?(object : Reference) : Bool
    @@kept_alive_mutex.synchronize { @@kept_alive.has_key?(object.to_unsafe.address) }
  end

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
  def self.wrap_slice(nothing : Nil) forall T
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
