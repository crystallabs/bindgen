#ifndef JSON_STREAM_HPP
#define JSON_STREAM_HPP

#include <optional>
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
	JsonStream &operator<<(const std::optional<T> &object) {
		if (object) {
			return *this << *object;
		} else {
			return *this << Null;
		}
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

// An associative array which, when serialized to JSON, maintains the insertion
// order of its elements.
template< typename K, typename V >
class JsonMap {
public:
	V &operator[](const K &key) {
		if (m_map.find(key) == m_map.end())
			m_keys.push_back(key);
		return m_map[key];
	}

	V *at(const K &key) {
		auto it = m_map.find(key);
		return it != m_map.end() ? &it->second : nullptr;
	}

	JsonStream &toJson(JsonStream &s) const {
		bool first = true;
		s << JsonStream::ObjectBegin;

		for (const auto &k : m_keys) {
			if (!first) s << JsonStream::Comma;
			s << *m_map.find(k);
			first = false;
		}

		s << JsonStream::ObjectEnd;
		return s;
	}

private:
	std::map<K, V> m_map;
	std::vector<K> m_keys;
};

template< typename K, typename V >
JsonStream &operator<<(JsonStream &s, const JsonMap<K, V> &value) {
	return value.toJson(s);
}

#endif // JSON_STREAM_HPP
