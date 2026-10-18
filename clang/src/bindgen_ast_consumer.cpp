#include "common.hpp"
#include "bindgen_ast_consumer.hpp"

#include "clang/ASTMatchers/ASTMatchersMacros.h"

#include "function_match_handler.hpp"
#include "record_match_handler.hpp"
#include "operator_match_handler.hpp"
#include "enum_match_handler.hpp"

#include "type_helper.hpp"

static llvm::cl::list<std::string> ClassList("c", llvm::cl::desc("Classes to inspect"), llvm::cl::value_desc("class"));
static llvm::cl::list<std::string> EnumList("e", llvm::cl::desc("Enums to inspect"), llvm::cl::value_desc("enum"));

// we don't support `operator,` and `operator->*`
AST_MATCHER(clang::FunctionDecl, isOverloadedOperator) {
	const auto oo = Node.getOverloadedOperator();
	return oo != clang::OO_None && oo != clang::OO_Comma && oo != clang::OO_ArrowStar;
}

// Matches a type registered as *name*, see `TypeHelper::registerTypeName`.
// Checked when matching, so it sees the names registered by then.
AST_MATCHER_P(clang::QualType, isRegisteredAs, std::string, name) {
	auto registered = TypeHelper::registeredTypeName(Node);
	return registered && *registered == name;
}

BindgenASTConsumer::BindgenASTConsumer(Document &doc)
	: m_functionHandler(nullptr), m_document(doc)
{
	this->m_matchFinders.push_back(makeBasicMatchFinder());

	// The operator methods rely on the document having been populated with
	// the classes, so a separate AST pass is necessary.
	this->m_matchFinders.push_back(makeDependentMatchFinder());
}

BindgenASTConsumer::~BindgenASTConsumer() {
}

clang::ast_matchers::MatchFinder BindgenASTConsumer::makeBasicMatchFinder() {
	using namespace clang::ast_matchers;

	MatchFinder finder {this->m_matchFinderOpts};

	for (const std::string &className : ClassList) {
		auto handler = std::make_unique<RecordMatchHandler>(m_document, className);

		// Instantiations can't be matched by name, see `gatherInstantiations`.
		if (!RecordMatchHandler::isInstantiation(className)) {
			DeclarationMatcher classMatcher = cxxRecordDecl(isDefinition(), hasName(className)).bind("recordDecl");
			finder.addMatcher(classMatcher, handler.get());
		}

		this->m_classHandlers.push_back(std::move(handler));
	}

	if (FunctionMatchHandler::isActive()) {
		DeclarationMatcher funcMatcher = functionDecl(unless(hasParent(cxxRecordDecl()))).bind("functionDecl");

		auto handler = std::make_unique<FunctionMatchHandler>(m_document);

		finder.addMatcher(funcMatcher, handler.get());
		this->m_functionHandler = std::move(handler);
	}

	for (const std::string &enumName : EnumList) {
		DeclarationMatcher enumMatcher = enumDecl(hasName(enumName)).bind("enumDecl");
		DeclarationMatcher typedefMatcher = typedefNameDecl(hasName(enumName)).bind("typedefNameDecl");

		auto handler = std::make_unique<EnumMatchHandler>(m_document, enumName);

		finder.addMatcher(enumMatcher, handler.get());
		finder.addMatcher(typedefMatcher, handler.get());
		this->m_enumHandlers.push_back(std::move(handler));
	}

	return finder;
}

clang::ast_matchers::MatchFinder BindgenASTConsumer::makeDependentMatchFinder() {
	using namespace clang::ast_matchers;

	MatchFinder finder {this->m_matchFinderOpts};

	for (const std::string &className : ClassList) {
		auto self = RecordMatchHandler::isInstantiation(className)
			? hasType(references(qualType(isRegisteredAs(className))))
			: hasType(references(cxxRecordDecl(hasName(className))));

		DeclarationMatcher operatorMatcher = functionDecl(
			isOverloadedOperator(),
			unless(cxxMethodDecl()),
			hasParameter(0, self)).bind("operatorDecl");

		auto handler = std::make_unique<OperatorMatchHandler>(m_document, className);

		finder.addMatcher(operatorMatcher, handler.get());
		this->m_operatorHandlers.push_back(std::move(handler));
	}

	return finder;
}

void BindgenASTConsumer::HandleTranslationUnit(clang::ASTContext &ctx) {
	TypeHelper::clearTypeNames();
	std::vector<std::pair<size_t, const clang::CXXRecordDecl *>> instantiations = this->gatherInstantiations(ctx);
	this->gatherTypeInfo(ctx);

	// Before matching, as the operators are added to the classes.
	for (const auto &instantiation : instantiations) {
		this->m_classHandlers[instantiation.first]->runOnDefinition(instantiation.second);
	}

	for (auto &finder : this->m_matchFinders) {
		finder.matchAST(ctx);
	}

	for (auto &handler : this->m_classHandlers) {
		handler->finish();
	}

	this->m_document.translationUnits++;
}

static void runTypeInfoResult(TypeInfoResult &info, const clang::ClassTemplateSpecializationDecl *spec, clang::ASTContext &ctx) {
	for (clang::Decl *decl : spec->decls()) {
		if (auto var_decl = llvm::dyn_cast<clang::VarDecl>(decl)) {
			if (var_decl->getName() == "isDefaultConstructible") {
				LiteralData data;
				TypeHelper::readValue(data, var_decl->getType(), ctx, var_decl->getInit());
				info.isDefaultConstructible = data.container.bool_value;
			}
		}
	}
}

void BindgenASTConsumer::gatherTypeInfo(clang::ASTContext &ctx) {
	for (auto decl : ctx.getTranslationUnitDecl()->decls()) {
		if (auto spec = llvm::dyn_cast<clang::ClassTemplateSpecializationDecl>(decl)) {
			if (spec->getQualifiedNameAsString() == "BindgenTypeInfo") {
				clang::QualType qt = spec->getTemplateArgs()[0].getAsType();
				std::string fullName = TypeHelper::registeredTypeName(qt).value_or(
					TypeHelper::fullyQualifiedName(qt, ctx));
				TypeInfoResult &info = m_document.type_infos[fullName];
				runTypeInfoResult(info, spec, ctx);
			}
		}
	}
}

// The template arguments written in the instantiation *name*, like `int` and
// `std::string` of `Map<int, std::string>`.
static std::vector<std::string> writtenTemplateArguments(const std::string &name) {
	std::vector<std::string> arguments;
	size_t open = name.find('<');
	size_t close = name.rfind('>');
	if (open == std::string::npos || close == std::string::npos || close < open) return arguments;

	std::string current;
	int depth = 0;

	for (size_t i = open + 1; i < close; i++) {
		char c = name[i];

		if (c == '<' || c == '(') depth++;
		if (c == '>' || c == ')') depth--;

		if (c == ',' && depth == 0) {
			arguments.push_back(current);
			current.clear();
		} else {
			current += c;
		}
	}

	arguments.push_back(current);

	for (std::string &argument : arguments) {
		size_t first = argument.find_first_not_of(' ');
		size_t last = argument.find_last_not_of(' ');
		argument = first == std::string::npos ? "" : argument.substr(first, last - first + 1);
	}

	return arguments;
}

// Names the type arguments of the *instantiation* as they are written in its
// configured *name*.  Clang stores them canonically, so a typedef like
// `std::string` would otherwise appear as `std::basic_string<char, ...>` in
// the members of the instantiation.
static void registerArgumentNames(const clang::CXXRecordDecl *instantiation, const std::string &name) {
	auto spec = llvm::dyn_cast<clang::ClassTemplateSpecializationDecl>(instantiation);
	if (!spec) return;

	const clang::TemplateArgumentList &arguments = spec->getTemplateArgs();
	std::vector<std::string> written = writtenTemplateArguments(name);

	for (size_t i = 0; i < written.size() && i < arguments.size(); i++) {
		const clang::TemplateArgument &argument = arguments[i];
		if (argument.getKind() != clang::TemplateArgument::Type || written[i].empty()) continue;

		clang::QualType type = argument.getAsType();
		if (!TypeHelper::registeredTypeName(type)) {
			TypeHelper::registerTypeName(type, written[i]);
		}
	}
}

std::vector<std::pair<size_t, const clang::CXXRecordDecl *>> BindgenASTConsumer::gatherInstantiations(clang::ASTContext &ctx) {
	std::vector<std::pair<size_t, const clang::CXXRecordDecl *>> result;

	for (auto decl : ctx.getTranslationUnitDecl()->decls()) {
		auto spec = llvm::dyn_cast<clang::ClassTemplateSpecializationDecl>(decl);
		if (!spec || spec->getQualifiedNameAsString() != "BindgenInstantiation") continue;

		const clang::TemplateArgumentList &args = spec->getTemplateArgs();
		uint64_t index = args[0].getAsIntegral().getZExtValue();
		if (index >= ClassList.size()) continue;

		// `BindgenInstantiation` made the record complete, unless it's invalid.
		const clang::CXXRecordDecl *record = args[1].getAsType()->getAsCXXRecordDecl();
		if (record && record->getDefinition() && !record->isInvalidDecl()) {
			TypeHelper::registerTypeName(TypeHelper::recordType(record), ClassList[index]);
			registerArgumentNames(record->getDefinition(), ClassList[index]);
			result.push_back(std::make_pair(index, record->getDefinition()));
		}
	}

	return result;
}
