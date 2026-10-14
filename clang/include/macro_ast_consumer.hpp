#ifndef MACRO_AST_CONSUMER_HPP
#define MACRO_AST_CONSUMER_HPP

#include "clang/AST/ASTConsumer.h"
#include "structures.hpp"
#include <vector>

// Reads the macro values evaluated by `MacroPragmaHandler`.
class MacroAstConsumer : public clang::ASTConsumer {
public:
	// Reads the macros in *macros* starting at index *first*.
	MacroAstConsumer(std::vector<Macro> &macros, size_t first);

	void checkVarDecl(clang::VarDecl *var, clang::ASTContext &ctx);

	void HandleTranslationUnit(clang::ASTContext &ctx) override;

private:
	std::vector<Macro> &m_macros;
	size_t m_first;
};

#endif // MACRO_AST_CONSUMER_HPP
