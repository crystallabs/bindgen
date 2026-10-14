#ifndef TYPE_HELPER_HPP
#define TYPE_HELPER_HPP

#include "structures.hpp"

namespace clang {
	class QualType;
	class ASTContext;
	class ParmVarDecl;
	class CXXRecordDecl;
};

namespace TypeHelper {
	// Returns the fully qualified name of *qt*, without tag keywords.
	std::string fullyQualifiedName(const clang::QualType &qt, const clang::ASTContext &ctx);

	// Returns the type of the *record*.
	clang::QualType recordType(const clang::CXXRecordDecl *record);

	// Names the type *qt* *name*, regardless of how it's spelled.  Used for
	// class template instantiations, which are known by the name the user
	// configured instead of the one Clang prints.
	void registerTypeName(const clang::QualType &qt, const std::string &name);

	// Forgets all names registered through `registerTypeName`.
	void clearTypeNames();

	// Returns the name registered for *qt*, if any.
	std::optional<std::string> registeredTypeName(const clang::QualType &qt);

	// Returns the qualified name of *record*, or its registered name.
	std::string recordName(const clang::CXXRecordDecl *record);

	Type qualTypeToType(const clang::QualType &qt, clang::ASTContext &ctx);

	void qualTypeToType(Type &target, const clang::QualType &qt, clang::ASTContext &ctx);

	bool readValue(LiteralData &literal, const clang::QualType &qt,
	  clang::ASTContext &ctx, const clang::Expr *expr);

	bool valueFromApValue(LiteralData &value, const clang::APValue &apValue, const clang::QualType &qt);

	Argument processFunctionParameter(const clang::ParmVarDecl *decl);

	void addFunctionParameters(const clang::FunctionDecl *func, Method &m);
};

#endif // RECORD_MATCH_HANDLER_HPP
