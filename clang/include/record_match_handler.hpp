#ifndef RECORD_MATCH_HANDLER_HPP
#define RECORD_MATCH_HANDLER_HPP

class RecordMatchHandler : public clang::ast_matchers::MatchFinder::MatchCallback {
public:
	RecordMatchHandler(Document &doc, const std::string &name);

	virtual void run(const clang::ast_matchers::MatchFinder::MatchResult &Result) override;

	// Exports the class *definition*, and its anonymous members.
	void runOnDefinition(const clang::CXXRecordDecl *definition);

	// Exports the class template instantiation *definition* found through
	// `BindgenInstantiation`.  A later match of the name, like of a typedef's
	// class, is ignored then.
	void runOnInstantiation(const clang::CXXRecordDecl *definition);

	// To be called once all matches were handled.  Reports an error if the
	// class turned out to be a class template only, or if the instantiation
	// couldn't be found.
	void finish();

	// Is *className* a class template instantiation, like `Foo<int>`?  These
	// are not found by name, see `BindgenASTConsumer::gatherInstantiations`.
	static bool isInstantiation(const std::string &className);

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
	bool m_instantiated = false; // Was it exported through `runOnInstantiation`?
	bool m_foundTemplate = false; // Was a class template of this name seen?

	// first = record definition, second = qualified type name
	std::vector<std::pair<const clang::CXXRecordDecl *, std::string>> m_classesToRun;
};

#endif // RECORD_MATCH_HANDLER_HPP
