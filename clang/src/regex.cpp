#include <regex.hpp>

#include <cstdio>
#include <cstdlib>
#include <stdexcept>

static const uint32_t PCRE_FLAGS = 0;

static void errorAndBail(const char *message, const std::string &expression, int code, int offset) {
	PCRE2_UCHAR error[256];
	pcre2_get_error_message(code, error, sizeof(error));

	fprintf(stderr, "%s:\n", message);
	fprintf(stderr, "  Error     : %s\n", error);
	fprintf(stderr, "  Expression: %s\n", expression.c_str());

	// Point to the error position
	if (offset >= 0) {
		fprintf(stderr, "              ");
		for (int i = 0; i < offset; i++)
			fputc(' ', stderr);
		fprintf(stderr, "^\n");
	}

	abort(); // Bail!
}

static pcre2_code *compileRegex(const std::string &expr) {
	int error = 0;
	PCRE2_SIZE offset = 0;

	pcre2_code *regex = pcre2_compile(
		reinterpret_cast<PCRE2_SPTR>(expr.c_str()), expr.size(), PCRE_FLAGS, &error, &offset, nullptr);

	if (regex == nullptr) {
		errorAndBail("Bad regular expression", expr, error, offset);
	}

	return regex;
}

Regex::Regex(const std::string &expression)
	: m_regex(nullptr)
{
	// If the expression is empty, we don't want to match anything.
	if (!expression.empty()) {
		this->m_regex = compileRegex(expression);
	}
}

Regex::Regex(const Regex &other)
	: m_regex(other.m_regex ? pcre2_code_copy(other.m_regex) : nullptr)
{
}

Regex::~Regex() {
	pcre2_code_free(this->m_regex);
}

bool Regex::isMatch(const std::string &text) const {
	if (this->m_regex == nullptr) return false;

	pcre2_match_data *data = pcre2_match_data_create_from_pattern(this->m_regex, nullptr);
	int r = pcre2_match(
		this->m_regex, reinterpret_cast<PCRE2_SPTR>(text.c_str()), text.size(), 0, 0, data, nullptr);
	pcre2_match_data_free(data);

	if (r == PCRE2_ERROR_NOMATCH) {
		return false;
	} else if (r >= 0) {
		return true; // Found a match!
	} else { // Unexpected error
		fprintf(stderr, "Regular expression failed with error %i\n", r);
		throw std::runtime_error("Regex error");
	}
}
