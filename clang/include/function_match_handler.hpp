#ifndef FUNCTION_MATCH_HANDLER_HPP
#define FUNCTION_MATCH_HANDLER_HPP

#include "clang/ASTMatchers/ASTMatchFinder.h"
#include "structures.hpp"
#include "regex.hpp"

namespace clang {
	class FunctionDecl;
}

class FunctionMatchHandler : public clang::ast_matchers::MatchFinder::MatchCallback {
public:
	FunctionMatchHandler(Document &doc);
	static bool isActive();

	virtual void run(const clang::ast_matchers::MatchFinder::MatchResult &Result) override;
	bool isFunctionInteresting(const std::string &name) const;
	void runOnFunction(const clang::FunctionDecl *func);

private:
	Document &m_document;
	Regex m_regex;
};

#endif // FUNCTION_MATCH_HANDLER_HPP
