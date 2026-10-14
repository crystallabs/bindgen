#ifndef BINDGEN_FRONTEND_ACTION_HPP
#define BINDGEN_FRONTEND_ACTION_HPP

class BindgenFrontendAction : public clang::ASTFrontendAction {
public:
	BindgenFrontendAction(Document &doc);

	// Adds the built-in system include paths to *ci*.
	static void addSystemIncludes(clang::CompilerInstance &ci);

	bool BeginInvocation(clang::CompilerInstance &ci) override;

	bool BeginSourceFileAction(clang::CompilerInstance &ci) override;

	std::unique_ptr<clang::ASTConsumer> CreateASTConsumer(clang::CompilerInstance &ci, llvm::StringRef file) override;

private:
	Document &m_document;
	size_t m_firstMacro; // Index of the first macro of this translation unit
};

#endif // BINDGEN_FRONTEND_ACTION_HPP
