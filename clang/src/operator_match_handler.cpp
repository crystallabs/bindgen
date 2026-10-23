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

	// A templated operator, like a friend `template <typename T>
	// operator<<(QDataStream &, const T &)`, has no concrete signature.
	if (op->isTemplated() || op->getTemplatedKind() != clang::FunctionDecl::TK_NonTemplate) return;
	if (op->getReturnType()->isDependentType()) return;
	if (op->isDeleted()) return;
	for (const clang::ParmVarDecl *param : op->parameters()) {
		if (param->getType()->isDependentType()) return;
	}

	Class *klass = this->m_document.classes.at(this->m_className);
	if (!klass) return;

	Method m { };
	if (runOnOperator(m, op)) {
		klass->methods.push_back(m);
	}
}

bool OperatorMatchHandler::runOnOperator(Method &m, const clang::FunctionDecl *op) {
	clang::ASTContext &ctx = op->getASTContext();

	// A free function of `member_functions`, like `qHash`, is a member method.
	m.type = op->isOverloadedOperator() ? Method::Operator : Method::MemberMethod;
	m.isFreeFunction = !op->isOverloadedOperator();
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
