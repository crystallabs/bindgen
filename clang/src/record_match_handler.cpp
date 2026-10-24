#include "common.hpp"
#include "clang/AST/RecordLayout.h"
#include "record_match_handler.hpp"
#include "enum_match_handler.hpp"
#include "type_helper.hpp"

RecordMatchHandler::RecordMatchHandler(Document &doc, const std::string &name)
	: m_document(doc), m_className(name)
{
}

void RecordMatchHandler::run(const clang::ast_matchers::MatchFinder::MatchResult &result) {
	const clang::CXXRecordDecl *record = result.Nodes.getNodeAs<clang::CXXRecordDecl>("recordDecl");
	if (!record || this->m_instantiated) return;

	// The pattern of a class template has no layout, only its
	// instantiations do.  It may also be another type of the same name in
	// a different scope, so only remember it for `finish()`.
	if (record->isDependentType()) {
		this->m_foundTemplate = true;
		return;
	}

	runOnDefinition(record);
}

void RecordMatchHandler::runOnDefinition(const clang::CXXRecordDecl *definition) {
	this->m_found = true;
	m_classesToRun.push_back(std::make_pair(definition, this->m_className));

	bool anonymous = false;
	while (!m_classesToRun.empty()) {
		const clang::CXXRecordDecl *record = m_classesToRun.back().first;
		std::string name = m_classesToRun.back().second;
		m_classesToRun.pop_back();

		Class klass;
		klass.name = name;
		klass.isAnonymous = anonymous;
		if (runOnRecord(klass, record)) {
			this->m_document.classes[name] = klass;
		}

		// every added record is anonymous except the first one
		anonymous = true;
	}
}

void RecordMatchHandler::runOnInstantiation(const clang::CXXRecordDecl *definition) {
	this->m_instantiated = true;
	runOnDefinition(definition);
}

bool RecordMatchHandler::isInstantiation(const std::string &className) {
	return className.find('<') != std::string::npos;
}

void RecordMatchHandler::finish() {
	if (this->m_found) return;

	if (this->m_foundTemplate) {
		this->m_document.errors.push_back(
			"'" + this->m_className + "' is a class template, which can't be wrapped as class."
			"  Wrap an instantiation like '" + this->m_className + "<int>' instead");
	} else if (isInstantiation(this->m_className)) {
		this->m_document.errors.push_back(
			"'" + this->m_className + "' doesn't name a complete class template instantiation");
	}
}

bool RecordMatchHandler::runOnMethod(Method &m, Class &klass, const clang::CXXMethodDecl *method, bool isSignal) {
	if (method->isDeleted())
		return false;

	m.className = TypeHelper::recordName(method->getParent());
	m.isConst = method->isConst();
	m.isVirtual = method->isVirtual();
#if CLANG_VERSION_MAJOR >= 18
	m.isPure = method->isPureVirtual();
#else
	m.isPure = method->isPure();
#endif
	m.isFinal = method->hasAttr<clang::FinalAttr>();
	m.isExternC = method->isExternC();
	m.isDeprecated = method->hasAttr<clang::DeprecatedAttr>();
	m.access = method->getAccess();
	m.isBuiltin = !method->isUserProvided();
	m.doc = TypeHelper::docComment(method);

	clang::ASTContext &ctx = method->getASTContext();
	const clang::CXXConstructorDecl* ctor = llvm::dyn_cast<clang::CXXConstructorDecl>(method);

	// Figure out what we have found
	if (ctor) {
		if (ctor->isMoveConstructor()) {
			return false; // Move constructors aren't really wrappable
		}

		m.type = ctor->isCopyConstructor() ? Method::CopyConstructor : Method::Constructor;
	} else if (llvm::isa<clang::CXXDestructorDecl>(method)) {
		klass.isDestructible = m.access != clang::AS_private;

		// For a destructor, only store if this type can be destructed publicly or not.
		return false;

	} else { // Normal method
		m.type = method->isStatic() ? Method::StaticMethod : Method::MemberMethod;
		m.name = method->getNameAsString();
		m.returnType = TypeHelper::qualTypeToType(method->getReturnType(), ctx);

		if (method->getOverloadedOperator() != clang::OO_None) {
			m.type = Method::Operator;
		} else if (auto conv = llvm::dyn_cast<clang::CXXConversionDecl>(method)) {
			m.type = Method::ConversionOperator; // TODO: Add conversion method support.
		} else if (isSignal && m.type == Method::MemberMethod && method->isUserProvided()) {
			m.type = Method::Signal;
		}
	}

	TypeHelper::addFunctionParameters(method, m);
	return true;
}

// Returns the alignment limit in bytes the packing of *record* sets, if it
// moves any of its members: 1 for `__attribute__((packed))`, or N for
// `#pragma pack(N)`.  Returns 0 if the record isn't packed, or the packing
// doesn't change its layout.
static int packAlignment(const clang::CXXRecordDecl *record) {
	clang::ASTContext &ctx = record->getASTContext();
	int64_t limit;

	if (record->hasAttr<clang::PackedAttr>()) {
		limit = 1;
	} else if (auto *pack = record->getAttr<clang::MaxFieldAlignmentAttr>()) {
		limit = pack->getAlignment() / ctx.getCharWidth();
	} else {
		return 0;
	}

	for (const clang::FieldDecl *field : record->fields()) {
		if (ctx.getTypeAlignInChars(field->getType()).getQuantity() > limit)
			return limit;
	}

	return 0;
}

bool RecordMatchHandler::runOnRecord(Class &klass, const clang::CXXRecordDecl *record) {
	const auto *typeInfoResult = m_document.findTypeInfoResult(klass.name);

	// `std::is_default_constructible` is false for an abstract class, which
	// a subclass still constructs through its default constructor.
	klass.hasDefaultConstructor = record->hasDefaultConstructor() &&
		(record->isAbstract() || !(typeInfoResult && !typeInfoResult->isDefaultConstructible));
	klass.hasCopyConstructor = record->hasCopyConstructorWithConstParam();
	klass.hasUserDeclaredConstructor = record->hasUserDeclaredConstructor();
	klass.isAbstract = record->isAbstract();
	klass.isFinal = record->isEffectivelyFinal();
	klass.isPolymorphic = record->isPolymorphic();
	klass.isTriviallyCopyable = record->isTriviallyCopyable();
	klass.isStandardLayout = record->isStandardLayout();
	klass.typeKind = record->getTagKind();
	klass.doc = TypeHelper::docComment(record);

	clang::QualType recordType = TypeHelper::recordType(record);
	clang::TypeInfo typeInfo = record->getASTContext().getTypeInfo(recordType);
	uint64_t bitSize = typeInfo.Width;
	if (typeInfo.isAlignRequired()) bitSize += typeInfo.Align;
	klass.byteSize = bitSize / 8;
	if (!record->isDependentType() && !record->isInvalidDecl())
		klass.packAlignment = packAlignment(record);

	for (clang::CXXBaseSpecifier base : record->bases()) {
		BaseClass b = handleBaseClass(base);

		// A base may not be at offset 0, then a pointer to it differs.
		if (!b.isVirtual && !record->isDependentType() && !record->isInvalidDecl()) {
			const clang::ASTRecordLayout &layout = record->getASTContext().getASTRecordLayout(record);
			b.offset = layout.getBaseClassOffset(base.getType()->getAsCXXRecordDecl()).getQuantity();
		}

		klass.bases.push_back(b);
	}

	bool isPublic = record->isStruct(); // Default public for structs!
	bool isSignal = false; // Qt signal support
	int unnamedCount = 0;

	for (clang::Decl *decl : record->decls()) {
		if (clang::CXXMethodDecl *method = llvm::dyn_cast<clang::CXXMethodDecl>(decl)) {
			Method m;
			if (runOnMethod(m, klass, method, isSignal)) {
				klass.methods.push_back(m);
			}
		} else if (clang::UsingDecl *usingDecl = llvm::dyn_cast<clang::UsingDecl>(decl)) {
			// A base method re-exported by `using Base::method;`, like the
			// `lock` of Qt 5's `QRecursiveMutex : private QMutex`.
			for (clang::UsingShadowDecl *shadow : usingDecl->shadows()) {
				clang::CXXMethodDecl *method = llvm::dyn_cast<clang::CXXMethodDecl>(shadow->getTargetDecl());
				if (!method || llvm::isa<clang::CXXConstructorDecl>(method)) continue;

				Method m;
				if (runOnMethod(m, klass, method, isSignal)) {
					m.className = klass.name;
					m.access = shadow->getAccess();
					klass.methods.push_back(m);
				}
			}
		} else if (clang::AccessSpecDecl *spec = llvm::dyn_cast<clang::AccessSpecDecl>(decl)) {
			isSignal = checkAccessSpecForSignal(spec);
		} else if (clang::FieldDecl *field = llvm::dyn_cast<clang::FieldDecl>(decl)) {
			Field f;
			if (runOnField(f, field)) {
				klass.fields.push_back(f);
			}
		} else if (clang::VarDecl *var = llvm::dyn_cast<clang::VarDecl>(decl)) {
			Field f;
			if (runOnStaticField(f, var)) {
				klass.fields.push_back(f);
			}
		} else if (clang::CXXRecordDecl *tag = llvm::dyn_cast<clang::CXXRecordDecl>(decl)) {
			if (!tag->getIdentifier()) {
				std::string ident = "Unnamed" + std::to_string(unnamedCount++);
				tag->setDeclName(&tag->getASTContext().Idents.get(ident));
				m_classesToRun.push_back(std::make_pair(tag, klass.name + "::" + ident));
			}
		} else if (clang::EnumDecl *enumeration = llvm::dyn_cast<clang::EnumDecl>(decl)) {
			if (!enumeration->getIdentifier()) {
				std::string ident = "Unnamed" + std::to_string(unnamedCount++);
				enumeration->setDeclName(&enumeration->getASTContext().Idents.get(ident));

				Enum e;
				e.name = klass.name + "::" + ident;
				e.isAnonymous = true;
				EnumMatchHandler enumHandler {this->m_document, e.name};
				if (enumHandler.runOnEnum(e, enumeration)) {
					this->m_document.enums[e.name] = e;
				}
			}
		}
	}

	return true;
}

static void readDefaultValue(Field &f, const clang::ValueDecl *decl, const clang::Expr *init) {
	if (init) {
		f.hasDefault = true;
		clang::QualType qt = decl->getType();
		if (qt->isArithmeticType()) { // Don't read string literals here (yet).
			if (!TypeHelper::readValue(f.value, qt, decl->getASTContext(), init)) {
				f.value.clear();
			}
		}
	} else {
		f.hasDefault = false;
	}
}

bool RecordMatchHandler::runOnField(Field &f, const clang::FieldDecl *field) {
	f.name = field->getNameAsString();
	f.access = field->getAccess();
	f.doc = TypeHelper::docComment(field);

	if (field->isBitField()) {
		f.bitField = field->getBitWidth()->EvaluateKnownConstInt(field->getASTContext()).getZExtValue();
	}

	clang::QualType qt = field->getType();
	clang::ASTContext &ctx = field->getASTContext();
	TypeHelper::qualTypeToType(f, qt, ctx);
	readDefaultValue(f, field, field->getInClassInitializer());

	// The layout, used to copy bit-fields into a `lib struct`.
	const clang::RecordDecl *record = field->getParent();
	if (!record->isDependentType() && !record->isInvalidDecl() && !qt->isIncompleteType()) {
		const clang::ASTRecordLayout &layout = ctx.getASTRecordLayout(record);
		f.bitOffset = layout.getFieldOffset(field->getFieldIndex());
		f.bitSize = ctx.getTypeSize(qt);
	}

	return true;
}

bool RecordMatchHandler::runOnStaticField(Field &f, const clang::VarDecl *var) {
	if (var->isStaticDataMember()) {
		f.name = var->getNameAsString();
		f.access = var->getAccess();
		f.isStatic = true;
		f.doc = TypeHelper::docComment(var);

		clang::QualType qt = var->getType();
		clang::ASTContext &ctx = var->getASTContext();
		TypeHelper::qualTypeToType(f, qt, ctx);
		readDefaultValue(f, var, var->getAnyInitializer());

		return true;
	}

	return false;
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

	// The base is named by its type rather than its declaration, so a template
	// instantiation keeps its arguments: `List<int>`, not `List`.  A typedef
	// is looked through, to name the class it refers to.
	const clang::CXXRecordDecl *record = base.getType()->getAsCXXRecordDecl();
	clang::ASTContext &ctx = record->getASTContext();
	clang::QualType type = base.getType().getUnqualifiedType();

	while (type->isTypedefNameType()) {
		type = type.getSingleStepDesugaredType(ctx);
	}

	if (auto name = TypeHelper::registeredTypeName(TypeHelper::recordType(record))) {
		b.name = *name;
	} else {
		b.name = TypeHelper::fullyQualifiedName(type, ctx);
	}

	return b;
}
