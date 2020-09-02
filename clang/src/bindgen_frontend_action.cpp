#include "common.hpp"
#include "generated.hpp"

#include "bindgen_frontend_action.hpp"
#include "bindgen_ast_consumer.hpp"
#include "preprocessor_handler.hpp"

#include "clang/Lex/Preprocessor.h"

bool BindgenFrontendAction::BeginInvocation(clang::CompilerInstance &ci) {
	clang::HeaderSearchOptions &headerOpts = ci.getHeaderSearchOpts();

	// Add built-in system include paths.
	for (const char *path : BG_SYSTEM_INCLUDES) {
		headerOpts.AddPath(llvm::StringRef(path), clang::frontend::System, false, false);
	}

	return true;
}

#if __clang_major__ < 5
bool BindgenFrontendAction::BeginSourceFileAction(clang::CompilerInstance &ci, llvm::StringRef)
#else
bool BindgenFrontendAction::BeginSourceFileAction(clang::CompilerInstance &ci)
#endif
{
	clang::Preprocessor &preprocessor = ci.getPreprocessor();
	preprocessor.addPPCallbacks(make_unique<PreprocessorHandler>(this->m_document, preprocessor));
	return true;
}

std::unique_ptr<clang::ASTConsumer> BindgenFrontendAction::CreateASTConsumer(clang::CompilerInstance &ci, llvm::StringRef file) {
	return make_unique<BindgenASTConsumer>(this->m_document, ci);
}
