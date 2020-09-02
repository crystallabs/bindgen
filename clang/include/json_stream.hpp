#ifndef JSON_STREAM_HPP
#define JSON_STREAM_HPP

#include "helper.hpp"
#include <ostream>
#include <vector>
#include <map>

/* Simple stream writer for JSON data. */
class JsonStream {
public:
	enum Terminal {
		ObjectBegin, // "{"
		ObjectEnd, // "}"
		ArrayBegin, // "["
		ArrayEnd, // "]"
		Comma, // ", "
		Separator, // ": "
		Null, // null
	};

	JsonStream(std::ostream &out);

	// Any integer type
	template<typename T, class = typename std::enable_if<std::is_integral<T>::value>::type>
	JsonStream &operator<<(T value) {
		this->m_out << value;
		return *this;
	}

	JsonStream &operator<<(double value);

	JsonStream &operator<<(bool value);

	JsonStream &operator<<(const char *value);

	JsonStream &operator<<(const std::string &value);

	template< typename T >
	JsonStream &operator<<(const std::vector<T> &vec) {
		bool first = true;
		*this << ArrayBegin;

		for (const T &v : vec) {
			if (!first) *this << Comma;
			*this << v;
			first = false;
		}

		*this << ArrayEnd;
		return *this;
	}

	template< typename K, typename V >
	JsonStream &operator<<(const std::map<K, V> &hash) {
		bool first = true;
		*this << ObjectBegin;

		for (const auto &kv : hash) {
			if (!first) *this << Comma;
			*this << kv;
			first = false;
		}

		*this << ObjectEnd;
		return *this;
	}

	template< typename U, typename V >
	JsonStream &operator<<(const std::pair<U, V> &pair) {
		return *this << pair.first << Separator << pair.second;
	}

	template< typename T >
	JsonStream &operator<<(const T *object) {
		if (object) {
			return *this << *object;
		} else {
			return *this << Null;
		}
	}

	template< typename T >
	JsonStream &operator<<(const CopyPtr<T> object) {
		return *this << object.ptr;
	}

	/* // Use once C++17 is enabled.
	template< typename ... Types >
	JsonStream &operator<<(const std::variant< Types ... > &variant) {
		std::visit([this](const auto &v){ *this << v; }, variant);
		return *this;
	}
	*/

	JsonStream &operator<<(Terminal terminal);

private:
	void printChar(char c);

	std::ostream &m_out;
};

#endif // JSON_STREAM_HPP
