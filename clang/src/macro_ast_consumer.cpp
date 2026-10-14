#include "macro_ast_consumer.hpp"
#include "type_helper.hpp"
#include "clang/AST/ASTContext.h"

MacroAstConsumer::MacroAstConsumer(std::vector<Macro> &macros, size_t first)
	: m_macros(macros), m_first(first)
{
}

void MacroAstConsumer::checkVarDecl(clang::VarDecl *var, clang::ASTContext &ctx) {
	llvm::StringRef varName = var->getName();

	if (!varName.consume_front("bg_macro_val_")) return; // Check prefix
	std::string macroName = varName.str();

	for (size_t i = this->m_first; i < this->m_macros.size(); i++) {
		Macro &m = this->m_macros[i];

		if (m.name == macroName) {
			m.type = TypeHelper::qualTypeToType(var->getType(), ctx);
			TypeHelper::readValue(m.evaluated, var->getType(), ctx, var->getInit());
			break;
		}
	}
}

void MacroAstConsumer::HandleTranslationUnit(clang::ASTContext &ctx) {
	if (this->m_first == this->m_macros.size()) return; // Nothing to read

	for (clang::Decl *decl : ctx.getTranslationUnitDecl()->decls()) {
		if (clang::VarDecl *varDecl = llvm::dyn_cast<clang::VarDecl>(decl)) {
			checkVarDecl(varDecl, ctx);
		}
	}
}
