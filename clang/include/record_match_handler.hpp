#ifndef RECORD_MATCH_HANDLER_HPP
#define RECORD_MATCH_HANDLER_HPP

class RecordMatchHandler : public clang::ast_matchers::MatchFinder::MatchCallback {
public:
	RecordMatchHandler(Document &doc, const std::string &name);

	virtual void run(const clang::ast_matchers::MatchFinder::MatchResult &Result) override;

	// To be called once all matches were handled.  Reports an error if the
	// class turned out to be a class template only.
	void finish();

private:
	bool runOnMethod(Method &m, Class &klass, const clang::CXXMethodDecl *method, bool isSignal);

	bool runOnRecord(Class &klass, const clang::CXXRecordDecl *record);

	bool runOnField(Field &f, const clang::FieldDecl *field);

	bool runOnStaticField(Field &f, const clang::VarDecl *var);

	bool checkAccessSpecForSignal(clang::AccessSpecDecl *spec);

	std::string getSourceFromRange(clang::SourceRange range, clang::SourceManager &sourceMgr);

	BaseClass handleBaseClass(const clang::CXXBaseSpecifier &base);

private:
	Document &m_document;
	std::string m_className;
	bool m_found = false; // Was a record of this name exported?
	bool m_foundTemplate = false; // Was a class template of this name seen?

	// first = record definition, second = qualified type name
	std::vector<std::pair<const clang::CXXRecordDecl *, std::string>> m_classesToRun;
};

#endif // RECORD_MATCH_HANDLER_HPP
