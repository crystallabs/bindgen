#ifndef ENUM_MATCH_HANDLER_HPP
#define ENUM_MATCH_HANDLER_HPP

class EnumMatchHandler : public clang::ast_matchers::MatchFinder::MatchCallback {
public:
	EnumMatchHandler(Document &doc, const std::string &name);

	virtual void run(const clang::ast_matchers::MatchFinder::MatchResult &Result) override;

	void runOnEnum(const clang::EnumDecl *enumeration);

	// Support for
	// 1. typedef'd enum types
	// 2. Qts `typedef QFlags<ENUM> ENUMs;` paradigm
	void runOnTypedef(const clang::TypedefNameDecl *typeDecl);

	void handleQFlagsType(const clang::ClassTemplateSpecializationDecl *tmpl);

private:
	Document &m_document;
	Enum m_enum;
};

#endif // ENUM_MATCH_HANDLER_HPP
