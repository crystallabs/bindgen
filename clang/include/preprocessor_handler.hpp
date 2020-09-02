#ifndef PREPROCESSOR_HANDLER_HPP
#define PREPROCESSOR_HANDLER_HPP

#include "regex.hpp"

class PreprocessorHandler : public clang::PPCallbacks {
public:
	PreprocessorHandler(Document &doc, clang::Preprocessor &preprocessor);

	void MacroDefined(const clang::Token &token, const clang::MacroDirective *md) override;

private:
	bool isMacroInteresting(const std::string &name);

	bool initializeMacro(Macro &m, const clang::Token &token, const clang::MacroDirective *md);

	clang::Preprocessor &m_preprocessor;
	Document &m_document;
	Regex m_regex;
};

#endif // PREPROCESSOR_HANDLER_HPP
