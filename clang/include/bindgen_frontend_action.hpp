#ifndef BINDGEN_FRONTEND_ACTION_HPP
#define BINDGEN_FRONTEND_ACTION_HPP

class BindgenFrontendAction : public clang::ASTFrontendAction {
public:
	bool BeginInvocation(clang::CompilerInstance &ci) override;

#if __clang_major__ < 5
	bool BeginSourceFileAction(clang::CompilerInstance &ci, llvm::StringRef) override;
#else
	bool BeginSourceFileAction(clang::CompilerInstance &ci) override;
#endif

	std::unique_ptr<clang::ASTConsumer> CreateASTConsumer(clang::CompilerInstance &ci, llvm::StringRef file) override;

private:
	Document m_document;
};

#endif // BINDGEN_FRONTEND_ACTION_HPPd
