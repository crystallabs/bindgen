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

  # Container for raw memory-data.  The `ptr` could be anything.
  struct CrystalSlice
    ptr : Void*
    size : LibC::Int
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

    # `#unsafe_fetch` and `#size` will be implemented by the wrapper class.

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
end
