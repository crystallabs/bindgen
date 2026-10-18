#include "type_helper.hpp"

#include "clang/AST/QualTypeNames.h"
#include "clang/Basic/Version.h"
#include "clang/AST/Type.h"
#include "clang/AST/Decl.h"
#include "clang/AST/DeclTemplate.h"
#include "clang/AST/ExprCXX.h"
#include "clang/AST/RawCommentList.h"
#include "llvm/ADT/StringExtras.h"

#include <map>

static std::optional<Template> handleTemplate(const clang::TemplateSpecializationType *tmpl, clang::ASTContext &ctx);
static std::optional<Type> handleValueArgument(const clang::TemplateArgument &argument, clang::ASTContext &ctx);
static bool tryReadStringConstructor(LiteralData &literal, const clang::CXXConstructExpr *expr);

// Names of the types registered through `TypeHelper::registerTypeName`, by
// their canonical type.
static std::map<const clang::Type *, std::string> registeredNames;

static const clang::Type *canonicalTypePtr(const clang::QualType &qt) {
	return qt.getCanonicalType().getUnqualifiedType().getTypePtr();
}

void TypeHelper::registerTypeName(const clang::QualType &qt, const std::string &name) {
	registeredNames[canonicalTypePtr(qt)] = name;
}

void TypeHelper::clearTypeNames() {
	registeredNames.clear();
}

std::optional<std::string> TypeHelper::registeredTypeName(const clang::QualType &qt) {
	auto it = registeredNames.find(canonicalTypePtr(qt));
	if (it == registeredNames.end()) return std::nullopt;
	return it->second;
}

clang::QualType TypeHelper::recordType(const clang::CXXRecordDecl *record) {
#if CLANG_VERSION_MAJOR >= 22
	return record->getASTContext().getCanonicalTagType(record);
#else
	return record->getASTContext().getRecordType(record);
#endif
}

std::string TypeHelper::recordName(const clang::CXXRecordDecl *record) {
	if (auto name = registeredTypeName(recordType(record))) {
		return *name;
	}

	return record->getQualifiedNameAsString();
}

static bool isIdentifierChar(char c) {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

// Removes tag keywords like `struct` from the type *name*.  Clang keeps those
// if they were written in the source, regardless of the printing policy.
//
// This is done on the printed name on purpose:  Dropping the keyword from the
// type itself means rebuilding it, with different code for Clang up to 16
// (`ElaboratedType`), 17 to 21 (`PrintingPolicy::SuppressElaboration`) and 22
// (keyword stored in `TagType`).  A tag keyword can't appear in a type name
// in any other role, so the textual removal is exact.
static void removeTagKeywords(std::string &name) {
	for (const std::string keyword : { "struct ", "class ", "union ", "enum " }) {
		size_t pos = 0;

		while ((pos = name.find(keyword, pos)) != std::string::npos) {
			if (pos == 0 || !isIdentifierChar(name[pos - 1])) {
				name.erase(pos, keyword.size());
			} else {
				pos += keyword.size();
			}
		}
	}
}

std::string TypeHelper::fullyQualifiedName(const clang::QualType &qt, const clang::ASTContext &ctx) {
	clang::PrintingPolicy policy(ctx.getPrintingPolicy());
	policy.SuppressTagKeyword = true; // No `struct`, `class`, ... prefix.

	std::string name = clang::TypeName::getFullyQualifiedName(qt, ctx, policy);
	removeTagKeywords(name);
	return name;
}

Type TypeHelper::qualTypeToType(const clang::QualType &qt, clang::ASTContext &ctx) {
	Type type;
	qualTypeToType(type, qt, ctx);
	return type;
}

// Looks through the typedefs a class template instantiation declares, like
// `QList<QString>::value_type`: Their names are not useful to the binding, but
// the types they refer to are.  Other typedefs are kept, as type rules may
// name them.
static clang::QualType desugarInstantiationTypedefs(clang::QualType qt, clang::ASTContext &ctx) {
	while (const auto *typedefType = qt->getAs<clang::TypedefType>()) {
		const clang::DeclContext *context = typedefType->getDecl()->getDeclContext();
		if (!llvm::isa<clang::ClassTemplateSpecializationDecl>(context)) break;

		qt = ctx.getQualifiedType(typedefType->desugar(), qt.getLocalQualifiers());
	}

	return qt;
}

void TypeHelper::qualTypeToType(Type &target, const clang::QualType &given, clang::ASTContext &ctx) {
	clang::QualType qt = desugarInstantiationTypedefs(given, ctx);

#if CLANG_VERSION_MAJOR >= 22
	clang::QualType ut = qt; // `ElaboratedType` is gone.
#else
	const auto *elab = llvm::dyn_cast<clang::ElaboratedType>(qt.getTypePtr());
	clang::QualType ut = elab ? elab->getNamedType() : qt;
#endif

	if (target.fullName.empty()) {
		target.fullName = fullyQualifiedName(qt, ctx);
	}

	if (const auto *arr = ctx.getAsArrayType(qt)) {
		// The pointers and references reached before the outermost array, like
		// in `int (*)[4]`, apply to the whole array.  Those reached between two
		// arrays, like in `int (*[2])[4]`, can't be described by the extents.
		// Keep the inner array as base type then, which isn't known.
		int extents = static_cast<int>(target.extents.size());

		if (extents == 0) {
			target.arrayPointer = target.pointer;
		} else if (target.pointer > target.arrayPointer + extents) {
			target.baseName = fullyQualifiedName(qt.getUnqualifiedType(), ctx);
			return;
		}

		// Do not support `T [static 4]` or `T [*]` for now
#if CLANG_VERSION_MAJOR >= 18
		if (arr->getSizeModifier() == clang::ArraySizeModifier::Normal) {
#else
		if (arr->getSizeModifier() == clang::ArrayType::ArraySizeModifier::Normal) {
#endif
			// DependentSizedArrayType may be in class templates; assume it doesn't exist
			// Do not support VariableArrayType for now
			if (const auto *carr = llvm::dyn_cast<clang::ConstantArrayType>(arr)) {
				target.pointer++;
				target.extents.push_back(carr->getSize().getZExtValue());
				return qualTypeToType(target, carr->getElementType(), ctx); // Recurse
			}
			else if (const auto *iarr = llvm::dyn_cast<clang::IncompleteArrayType>(arr)) {
				target.pointer++;
				target.extents.push_back(0);
				return qualTypeToType(target, iarr->getElementType(), ctx); // Recurse
			}
		}

		// Unsupported arrays become the base type.
		if (extents == 0) {
			target.arrayPointer = 0;
		}
	}

	if (qt->isReferenceType() || qt->isPointerType()) {
		target.isReference = target.isReference || qt->isReferenceType();
		target.isMove = target.isMove || qt->isRValueReferenceType();
		target.pointer++;
		return qualTypeToType(target, qt->getPointeeType(), ctx); // Recurse
	}

	// Not a reference or pointer.
	target.isConst = qt.isConstQualified();
	target.isVoid = qt->isVoidType();
	target.isBuiltin = qt->isBuiltinType();
	target.baseName = fullyQualifiedName(qt.getUnqualifiedType(), ctx);

	// Instantiations to be wrapped are known by their configured name.
	if (auto name = registeredTypeName(qt)) {
		target.baseName = *name;
	}

	if (const auto *tmpl = llvm::dyn_cast<clang::TemplateSpecializationType>(ut.getTypePtr())) {
		target.templ = handleTemplate(tmpl, ctx);
		if (target.templ) {
			target.templ->fullName = target.baseName;
		}
	}
}

static std::optional<Template> handleTemplate(const clang::TemplateSpecializationType *tmpl, clang::ASTContext &ctx) {
	Template t;

	if (!tmpl) return std::nullopt;

	if (const clang::TemplateDecl *decl = tmpl->getTemplateName().getAsTemplateDecl()) {
		t.baseName = decl->getQualifiedNameAsString();
	}

	for (const clang::TemplateArgument &argument : tmpl->template_arguments()) {
		if (argument.getKind() == clang::TemplateArgument::Type) {
			t.arguments.push_back(TypeHelper::qualTypeToType(argument.getAsType(), ctx));
		} else if (auto value = handleValueArgument(argument, ctx)) {
			t.arguments.push_back(*value);
		} else {
			return std::nullopt;
		}
	}

	return t;
}

// Describes the non-type template *argument* as type named after its value,
// like `4` in `std::array<int, 4>`.  Only integral values are supported.
static std::optional<Type> handleValueArgument(const clang::TemplateArgument &argument, clang::ASTContext &ctx) {
	llvm::APSInt value;
	clang::QualType qt;

	if (argument.getKind() == clang::TemplateArgument::Integral) {
		value = argument.getAsIntegral();
		qt = argument.getIntegralType();
	} else if (argument.getKind() == clang::TemplateArgument::Expression) {
		const clang::Expr *expr = argument.getAsExpr();
		clang::Expr::EvalResult result;

		if (expr->isValueDependent() || !expr->EvaluateAsInt(result, ctx))
			return std::nullopt;

		value = result.Val.getInt();
		qt = expr->getType();
	} else {
		return std::nullopt;
	}

	Type type;
	if (qt->isBooleanType()) {
		type.baseName = value.getBoolValue() ? "true" : "false";
	} else {
		type.baseName = llvm::toString(value, 10);
	}

	type.fullName = type.baseName;
	return type;
}

Argument TypeHelper::processFunctionParameter(const clang::ParmVarDecl *decl) {
	clang::ASTContext &ctx = decl->getASTContext();
	Argument arg;

	clang::QualType qt = decl->getType();
	qualTypeToType(arg, qt, ctx);
	arg.name = decl->getQualifiedNameAsString();
	arg.isVariadic = false;
	arg.hasDefault = decl->hasDefaultArg();
	arg.value.clear();

	// If the parameter has a default value, try to figure out this value.  Can
	// fail if e.g. the call has side-effects (Like calling another method).  Will
	// work for constant expressions though, like `true` or `3 + 5`.
	if (arg.hasDefault) {
		TypeHelper::readValue(arg.value, qt, ctx, decl->getDefaultArg());
	}

	return arg;
}

static bool describesStringClass(const clang::CXXConstructorDecl *ctorDecl) {
	std::string name = ctorDecl->getParent()->getQualifiedNameAsString();
	// Newer Clang versions don't print the inline namespace.
	return name == "std::basic_string" || name == "std::__cxx11::basic_string" || name == "std::__1::basic_string";
}

static bool stringLiteralFromExpression(LiteralData &literal, const clang::Expr *expr) {
	if (const clang::MaterializeTemporaryExpr *argExpr = llvm::dyn_cast<clang::MaterializeTemporaryExpr>(expr)) {
		return stringLiteralFromExpression(literal, argExpr->getSubExpr());
	} else if (const clang::ExprWithCleanups *cleanupExpr = llvm::dyn_cast<clang::ExprWithCleanups>(expr)) {
		return stringLiteralFromExpression(literal, cleanupExpr->getSubExpr());
	} else if (const clang::CXXBindTemporaryExpr *bindExpr = llvm::dyn_cast<clang::CXXBindTemporaryExpr>(expr)) {
		return stringLiteralFromExpression(literal, bindExpr->getSubExpr());
	} else if (const clang::CastExpr *castExpr = llvm::dyn_cast<clang::CastExpr>(expr)) {
		return stringLiteralFromExpression(literal, castExpr->getSubExprAsWritten());
	} else if (const clang::CXXConstructExpr *ctorExpr = llvm::dyn_cast<clang::CXXConstructExpr>(expr)) {
		return tryReadStringConstructor(literal, ctorExpr);
	} else if (const clang::ParenExpr *parenExpr = llvm::dyn_cast<clang::ParenExpr>(expr)) {
		return stringLiteralFromExpression(literal, parenExpr->getSubExpr());
	} else if (const clang::StringLiteral *strExpr = llvm::dyn_cast<clang::StringLiteral>(expr)) {
		// We found it!
		literal = strExpr->getString().str();
		return true;
	} else { // Failed to destructure.
		return false;
	}
}

static bool tryReadStringConstructor(LiteralData &literal, const clang::CXXConstructExpr *expr) {
	if (!describesStringClass(expr->getConstructor())) {
		return false;
	}

	// The constructor call needs to have no (= empty) or a single argument.
	if (expr->getNumArgs() == 0) { // This is an empty string!
		literal = std::string();
		return true;
	} else if (expr->getNumArgs() == 1) {
		return stringLiteralFromExpression(literal, expr->getArg(0));
	} else { // No rules for more than one argument.
		return false;
	}
}

bool TypeHelper::valueFromApValue(LiteralData &value, const clang::APValue &apValue, const clang::QualType &qt) {
	if (qt->isPointerType()) {
		// For a pointer-type, just store if it was `nullptr` (== true).
		value = apValue.isNullPointer();
	} else if (qt->isBooleanType()) {
		value = apValue.getInt().getBoolValue();
	} else if (qt->isIntegerType()) {
		const llvm::APSInt &v = apValue.getInt();
		if (qt->isSignedIntegerType())
			value = v.getExtValue();
		else {
			value = v.getZExtValue();
		}
	} else if (qt->isFloatingType()) {
		const llvm::APFloat &f = apValue.getFloat();
		if (&f.getSemantics() == &llvm::APFloat::IEEEsingle()) {
			value = static_cast<double>(f.convertToFloat());
		} else if (&f.getSemantics() == &llvm::APFloat::IEEEdouble()) {
			value = f.convertToDouble();
		} else {
			return false;
		}
	} else {
		return false;
	}

	return true;
}

bool TypeHelper::readValue(LiteralData &literal, const clang::QualType &qt,
	clang::ASTContext &ctx, const clang::Expr *expr) {
	clang::Expr::EvalResult result;

	if (!expr) return false; // Sanity check

	if (!expr->EvaluateAsRValue(result, ctx)) {
		// Failed to evaluate - Try to unpack this expression
		return stringLiteralFromExpression(literal, expr);
	}

	if (result.HasSideEffects || result.HasUndefinedBehavior) {
		return false; // Don't accept if there are side-effects or undefined behaviour.
	}

	if (qt->isPointerType() && qt->getPointeeType()->isCharType()) {
		return stringLiteralFromExpression(literal, expr);
	} else {
		return TypeHelper::valueFromApValue(literal, result.Val, qt);
	}
}

void TypeHelper::addFunctionParameters(const clang::FunctionDecl *func, Method &m) {
	for (unsigned i = 0; i < func->getNumParams(); i++) {
		Argument arg = TypeHelper::processFunctionParameter(func->parameters()[i]);

		if (arg.hasDefault && m.firstDefaultArgument < 0)
			m.firstDefaultArgument = i;

		m.arguments.push_back(arg);
	}

	if (func->isVariadic()) { // Support vararg functions
		Argument arg;
		arg.name = "...";
		arg.isVariadic = true;
		arg.hasDefault = false;
		m.arguments.push_back(arg);
	}
}

// Returns the declaration *decl* was instantiated from, or *decl* itself.
// Clang doesn't attach comments to implicit template instantiations.
static const clang::Decl *templatePattern(const clang::Decl *decl) {
	if (auto *record = llvm::dyn_cast<clang::CXXRecordDecl>(decl)) {
		if (auto *pattern = record->getTemplateInstantiationPattern())
			return pattern;
	} else if (auto *func = llvm::dyn_cast<clang::FunctionDecl>(decl)) {
		if (auto *pattern = func->getTemplateInstantiationPattern())
			return pattern;
	} else if (auto *enumeration = llvm::dyn_cast<clang::EnumDecl>(decl)) {
		if (auto *pattern = enumeration->getTemplateInstantiationPattern())
			return pattern;
	} else if (auto *var = llvm::dyn_cast<clang::VarDecl>(decl)) {
		if (auto *pattern = var->getTemplateInstantiationPattern())
			return pattern;
	} else if (auto *field = llvm::dyn_cast<clang::FieldDecl>(decl)) {
		// Fields have no link to their pattern, find it by name.
		auto *record = llvm::dyn_cast<clang::CXXRecordDecl>(field->getParent());
		auto *pattern = record ? record->getTemplateInstantiationPattern() : nullptr;
		if (pattern && field->getIdentifier()) {
			for (auto *candidate : pattern->lookup(field->getDeclName())) {
				if (llvm::isa<clang::FieldDecl>(candidate))
					return candidate;
			}
		}
	}

	return decl;
}

std::string TypeHelper::docComment(const clang::Decl *decl) {
	decl = templatePattern(decl);
	clang::ASTContext &ctx = decl->getASTContext();
	const clang::RawComment *comment = ctx.getRawCommentForAnyRedecl(decl);
	if (!comment) return std::string();

	return comment->getFormattedText(ctx.getSourceManager(), ctx.getDiagnostics());
}
