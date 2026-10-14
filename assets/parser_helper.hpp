#include <type_traits>

template< typename T >
struct BindgenTypeInfo {
  static const bool isDefaultConstructible = std::is_default_constructible<T>::value;
};

// Instantiated for each class template instantiation *T* to inspect, with *I*
// being its index in the list of classes.  `size` makes *T* complete.
template< int I, typename T >
struct BindgenInstantiation {
  static const unsigned long size = sizeof(T);
};
