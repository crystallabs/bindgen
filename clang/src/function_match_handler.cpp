#include "common.hpp"
#include "function_match_handler.hpp"
#include "type_helper.hpp"

static llvm::cl::opt<std::string> FunctionRegex("f", llvm::cl::desc("Functions to inspect"), llvm::cl::value_desc("function regex"));

FunctionMatchHandler::FunctionMatchHandler(Document &doc)
	: m_document(doc), m_regex(FunctionRegex)
{
}

bool FunctionMatchHandler::isActive() {
	return FunctionRegex.empty() == false;
}

void FunctionMatchHandler::run(const clang::ast_matchers::MatchFinder::MatchResult &result) {
	const clang::FunctionDecl *func = result.Nodes.getNodeAs<clang::FunctionDecl>("functionDecl");
	if (func) runOnFunction(func);
}

bool FunctionMatchHandler::isFunctionInteresting(const std::string &name) const {
	return this->m_regex.isMatch(name);
}

static std::string getFunctionParentName(const std::string &fullName, const std::string &funcName) {
	if (funcName == fullName) {
		return "::";
	} else {
		int parentLen = fullName.size() - funcName.size() - 2; // Substract "::" too
		return fullName.substr(0, parentLen);
	}
}

static Method buildMethod(const clang::FunctionDecl *func, const std::string &fullName) {
	Method m;
	m.name = func->getNameAsString();
	m.className = getFunctionParentName(fullName, m.name);
	m.type = Method::StaticMethod;
	m.isConst = false;
	m.isVirtual = false;
	m.isPure = false;
	m.isExternC = func->isExternC() || func->isInExternCContext();
	m.access = clang::AS_public; // Global functions are always public

	clang::ASTContext &ctx = func->getASTContext();
	m.returnType = TypeHelper::qualTypeToType(func->getReturnType(), ctx);
	TypeHelper::addFunctionParameters(func, m);

	return m;
}

void FunctionMatchHandler::runOnFunction(const clang::FunctionDecl *func) {
	std::string fullName = func->getQualifiedNameAsString();

	if (isFunctionInteresting(fullName)) {
		this->m_document.functions.push_back(buildMethod(func, fullName));
	}
}
