#ifndef HELPER_HPP
#define HELPER_HPP

#include <memory>

/* Pointer guard, which copies the instance on each copy.
 * Useful to mark optional data.
 */
template< typename T >
struct CopyPtr {
	T *ptr = nullptr;

	CopyPtr() = default;
	CopyPtr(T *ptr) : ptr(ptr) { }
	CopyPtr(const T &t) : ptr(new T(t)) { }
	CopyPtr(const CopyPtr<T> &other) {
		if (other.ptr) {
			this->ptr = new T(*other.ptr);
		}
	}
	CopyPtr(CopyPtr<T> &&other) : ptr(other.ptr) {
		other.ptr = nullptr;
	}

	const T *operator=(const T *other) {
		delete this->ptr;
		this->ptr = new T(*other);
		return other;
	}

	T *operator=(T *other) {
		delete this->ptr;
		this->ptr = other;
		return other;
	}

	const T &operator=(const T &other) {
		delete this->ptr;
		this->ptr = new T(other);
		return other;
	}

	operator bool() const {
		return this->ptr != nullptr;
	}

	CopyPtr<T> &operator=(const CopyPtr<T> &other) {
		delete this->ptr;
		this->ptr = new T(*other.ptr);
		return *this;
	}

	CopyPtr<T> &operator=(CopyPtr<T> &&other) {
		delete this->ptr;
		this->ptr = other.ptr;
		other.ptr = nullptr;
		return *this;
	}

	~CopyPtr() {
		delete this->ptr;
	}

	T *operator->() { return this->ptr; }
	const T *operator->() const { return this->ptr; }

	T &operator*() { return *this->ptr; }
	const T &operator*() const { return *this->ptr; }
};

// compatibility for C++11
template< typename T, typename... Args >
std::unique_ptr<T> make_unique(Args&&... args)
{
	return std::unique_ptr<T>(new T(std::forward<Args>(args)...));
}

#endif // HELPER_HPP
