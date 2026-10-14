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
		DeclarationMatcher classMatcher = cxxRecordDecl(isDefinition(), hasName(className)).bind("recordDecl");

		auto handler = std::make_unique<RecordMatchHandler>(m_document, className);

		finder.addMatcher(classMatcher, handler.get());
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
		DeclarationMatcher operatorMatcher = functionDecl(
			isOverloadedOperator(),
			unless(cxxMethodDecl()),
			hasParameter(0, hasType(references(cxxRecordDecl(hasName(className)))))).bind("operatorDecl");

		auto handler = std::make_unique<OperatorMatchHandler>(m_document, className);

		finder.addMatcher(operatorMatcher, handler.get());
		this->m_operatorHandlers.push_back(std::move(handler));
	}

	return finder;
}

void BindgenASTConsumer::HandleTranslationUnit(clang::ASTContext &ctx) {
	this->gatherTypeInfo(ctx);
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
				std::string fullName = TypeHelper::fullyQualifiedName(qt, ctx);
				TypeInfoResult &info = m_document.type_infos[fullName];
				runTypeInfoResult(info, spec, ctx);
			}
		}
	}
}
