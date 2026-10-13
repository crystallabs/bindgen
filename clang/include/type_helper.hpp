#ifndef TYPE_HELPER_HPP
#define TYPE_HELPER_HPP

#include "structures.hpp"

namespace clang {
	class QualType;
	class ASTContext;
	class ParmVarDecl;
};

namespace TypeHelper {
	// Returns the fully qualified name of *qt*, without tag keywords.
	std::string fullyQualifiedName(const clang::QualType &qt, const clang::ASTContext &ctx);

	Type qualTypeToType(const clang::QualType &qt, clang::ASTContext &ctx);

	void qualTypeToType(Type &target, const clang::QualType &qt, clang::ASTContext &ctx);

	bool readValue(LiteralData &literal, const clang::QualType &qt,
	  clang::ASTContext &ctx, const clang::Expr *expr);

	bool valueFromApValue(LiteralData &value, const clang::APValue &apValue, const clang::QualType &qt);

	Argument processFunctionParameter(const clang::ParmVarDecl *decl);

	void addFunctionParameters(const clang::FunctionDecl *func, Method &m);
};

#endif // RECORD_MATCH_HANDLER_HPP
