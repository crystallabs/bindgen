#ifndef MACRO_FRONTEND_ACTION_HPP
#define MACRO_FRONTEND_ACTION_HPP

// Evaluates the values of the macros found by `BindgenFrontendAction`.  This
// is done in a second pass, parsing a file built by `evaluationFile()`.
class MacroFrontendAction : public clang::ASTFrontendAction {
public:
	MacroFrontendAction(Document &doc);

	// Does *doc* contain macros which can be evaluated?
	static bool isActive(const Document &doc);

	// Builds the source which includes *sources*, followed by a variable
	// definition per macro to evaluate.
	static std::string evaluationFile(const Document &doc, const std::vector<std::string> &sources);

	bool BeginInvocation(clang::CompilerInstance &ci) override;

	std::unique_ptr<clang::ASTConsumer> CreateASTConsumer(clang::CompilerInstance &ci, llvm::StringRef file) override;

private:
	Document &m_document;
};

#endif // MACRO_FRONTEND_ACTION_HPP
