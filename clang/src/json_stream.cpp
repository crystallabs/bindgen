#include "json_stream.hpp"

#include <cstdio>

/* Simple stream writer for JSON data. */
JsonStream::JsonStream(std::ostream &out)
: m_out(out)
{
	//
}

JsonStream &JsonStream::operator<<(double value) {
	this->m_out << value;
	return *this;
}

JsonStream &JsonStream::operator<<(bool value) {
	if (value)
		this->m_out << "true";
	else
		this->m_out << "false";

	return *this;
}

JsonStream &JsonStream::operator<<(const char *value) {
	this->m_out << '"';

	while (*value) {
		printChar(*value);
		value++;
	}

	this->m_out << '"';
	return *this;
}

JsonStream &JsonStream::operator<<(const std::string &value) {
	this->m_out << '"';

	for (char c : value)
		printChar(c);

	this->m_out << '"';
	return *this;
}

JsonStream &JsonStream::operator<<(Terminal terminal) {
	switch (terminal) {
		case ObjectBegin: this->m_out << "{"; break;
		case ObjectEnd: this->m_out << "}"; break;
		case ArrayBegin: this->m_out << "["; break;
		case ArrayEnd: this->m_out << "]"; break;
		case Comma: this->m_out << ", "; break;
		case Separator: this->m_out << ": "; break;
		case Null: this->m_out << "null"; break;
	}

	return *this;
}

void JsonStream::printChar(char c) {
	switch (c) {
		case '\\': this->m_out << "\\\\"; break;
		case '"': this->m_out << "\\\""; break;
		case '\n': this->m_out << "\\n"; break;
		case '\t': this->m_out << "\\t"; break;
		default:
			// JSON doesn't allow other control characters in strings either.
			if (static_cast<unsigned char>(c) < 0x20) {
				char escaped[7];
				snprintf(escaped, sizeof(escaped), "\\u%04x", c);
				this->m_out << escaped;
			} else {
				this->m_out << c;
			}
			break;
	}
}
