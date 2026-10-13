#ifndef REGEX_HPP
#define REGEX_HPP

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <string>

// PCRE2 based regex helper.  Aborts if a regex is broken.
class Regex {
public:
	Regex(const std::string &expression);
	Regex(const Regex &other);
	~Regex();

	bool isMatch(const std::string &text) const;

private:
	pcre2_code *m_regex;
};

#endif // REGEX_HPP
