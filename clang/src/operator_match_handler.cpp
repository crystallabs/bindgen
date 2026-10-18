#include "common.hpp"
#include "operator_match_handler.hpp"
#include "type_helper.hpp"

OperatorMatchHandler::OperatorMatchHandler(Document &doc, const std::string &name)
	: m_document(doc), m_className(name)
{
}

void OperatorMatchHandler::run(const clang::ast_matchers::MatchFinder::MatchResult &result) {
	const auto *op = result.Nodes.getNodeAs<clang::FunctionDecl>("operatorDecl");
	if (!op) return;

	Class *klass = this->m_document.classes.at(this->m_className);
	if (!klass) return;

	Method m { };
	if (runOnOperator(m, op)) {
		klass->methods.push_back(m);
	}
}

bool OperatorMatchHandler::runOnOperator(Method &m, const clang::FunctionDecl *op) {
	clang::ASTContext &ctx = op->getASTContext();

	m.type = Method::Operator;
	m.name = op->getNameAsString();
	m.access = clang::AS_public;
	m.isDeprecated = op->hasAttr<clang::DeprecatedAttr>();
	m.doc = TypeHelper::docComment(op);
	m.returnType = TypeHelper::qualTypeToType(op->getReturnType(), ctx);
	TypeHelper::addFunctionParameters(op, m);

	// remove self argument
	m.className = m.arguments[0].baseName;
	m.isConst = m.arguments[0].isConst;
	m.arguments.erase(m.arguments.begin());

	return true;
}
