#include "common.hpp"
#include "record_match_handler.hpp"
#include "type_helper.hpp"

RecordMatchHandler::RecordMatchHandler(Document &doc, const std::string &name)
	: m_document(doc)
{
	this->m_class.name = name;
}

void RecordMatchHandler::run(const clang::ast_matchers::MatchFinder::MatchResult &result) {
	const clang::CXXRecordDecl *record = result.Nodes.getNodeAs<clang::CXXRecordDecl>("recordDecl");
	if (record) runOnRecord(record);
}

void RecordMatchHandler::runOnMethod(const clang::CXXMethodDecl *method, bool isSignal) {
	Method m;
	m.className = method->getParent()->getQualifiedNameAsString();
	m.isConst = method->isConst();
	m.isVirtual = method->isVirtual();
	m.isPure = method->isPure();
	m.isExternC = method->isExternC();
	m.access = method->getAccess();

	clang::ASTContext &ctx = method->getASTContext();
	const clang::CXXConstructorDecl* ctor = llvm::dyn_cast<clang::CXXConstructorDecl>(method);

	// Figure out what we have found
	if (ctor) {
		if (ctor->isMoveConstructor()) {
			return; // Move constructors aren't really wrappable
		}

		m.type = ctor->isCopyConstructor() ? Method::CopyConstructor : Method::Constructor;
	} else if (llvm::isa<clang::CXXDestructorDecl>(method)) {
		this->m_class.isDestructible = m.access != clang::AS_private;

		// For a destructor, only store if this type can be destructed publicly or not.
		return;

	} else { // Normal method
		m.type = method->isStatic() ? Method::StaticMethod : Method::MemberMethod;
		m.name = method->getNameAsString();
		m.returnType = TypeHelper::qualTypeToType(method->getReturnType(), ctx);

		if (method->getOverloadedOperator() != clang::OO_None) {
			m.type = Method::Operator;
		} else if (auto conv = llvm::dyn_cast<clang::CXXConversionDecl>(method)) {
			m.type = Method::Operator; // TODO: Add conversion method support.

		} else if (isSignal && m.type == Method::MemberMethod && method->isUserProvided()) {
			m.type = Method::Signal;
		}
	}

	TypeHelper::addFunctionParameters(method, m);
	this->m_class.methods.push_back(m);
}

void RecordMatchHandler::runOnRecord(const clang::CXXRecordDecl *record) {
	this->m_class.hasDefaultConstructor = record->hasDefaultConstructor();
	this->m_class.hasCopyConstructor = record->hasCopyConstructorWithConstParam();
	this->m_class.isAbstract = record->isAbstract();
	this->m_class.isClass = record->isClass();

	clang::TypeInfo typeInfo = record->getASTContext().getTypeInfo(record->getTypeForDecl());
	uint64_t bitSize = typeInfo.Width;
	if (typeInfo.AlignIsRequired) bitSize += typeInfo.Align;
	this->m_class.byteSize = bitSize / 8;

	for (clang::CXXBaseSpecifier base : record->bases()) {
		this->m_class.bases.push_back(handleBaseClass(base));
	}

	bool isPublic = record->isStruct(); // Default public for structs!
	bool isSignal = false; // Qt signal support

	for (clang::Decl *decl : record->decls()) {
		if (clang::CXXMethodDecl *method = llvm::dyn_cast<clang::CXXMethodDecl>(decl)) {
			runOnMethod(method, isSignal);
		} else if (clang::AccessSpecDecl *spec = llvm::dyn_cast<clang::AccessSpecDecl>(decl)) {
			isSignal = checkAccessSpecForSignal(spec);
		} else if (clang::FieldDecl *field = llvm::dyn_cast<clang::FieldDecl>(decl)) {
			runOnField(field);
		}
	}

	this->m_document.classes[this->m_class.name] = this->m_class;
}

void RecordMatchHandler::runOnField(const clang::FieldDecl *field) {
	Field f;
	f.name = field->getNameAsString();
	f.access = field->getAccess();
	// f.bitField = TODO

	TypeHelper::qualTypeToType(f, field->getType(), field->getASTContext());
	this->m_class.fields.push_back(f);
}

bool RecordMatchHandler::checkAccessSpecForSignal(clang::AccessSpecDecl *spec) {
	clang::SourceRange range = spec->getSourceRange();
	clang::SourceManager &sourceMgr = spec->getASTContext().getSourceManager();
	std::string snippet = getSourceFromRange(range, sourceMgr);

	return (snippet == "signals" || snippet == "Q_SIGNALS");
}

std::string RecordMatchHandler::getSourceFromRange(clang::SourceRange range, clang::SourceManager &sourceMgr) {
	std::pair<clang::FileID, unsigned> begin = sourceMgr.getDecomposedExpansionLoc(range.getBegin());
	std::pair<clang::FileID, unsigned> end = sourceMgr.getDecomposedExpansionLoc(range.getEnd());

	if (begin.first != end.first)
		return std::string();

	bool invalid = false;
	llvm::StringRef fileBuffer = sourceMgr.getBufferData(begin.first, &invalid);

	if (invalid)
		return std::string();

	unsigned int length = end.second - begin.second;
	return fileBuffer.substr(begin.second, length).str();
}

BaseClass RecordMatchHandler::handleBaseClass(const clang::CXXBaseSpecifier &base) {
	BaseClass b;

	b.isVirtual = base.isVirtual();
	b.inheritedConstructor = base.getInheritConstructors();
	b.access = base.getAccessSpecifier();
	b.name = base.getType()->getAsCXXRecordDecl()->getNameAsString();

	return b;
}
