#include "common.hpp"
#include "generated.hpp"

#include "bindgen_frontend_action.hpp"
#include "bindgen_ast_consumer.hpp"
#include "preprocessor_handler.hpp"

#include "clang/Lex/Preprocessor.h"

BindgenFrontendAction::BindgenFrontendAction(Document &doc)
	: m_document(doc)
{
}

void BindgenFrontendAction::addSystemIncludes(clang::CompilerInstance &ci) {
	clang::HeaderSearchOptions &headerOpts = ci.getHeaderSearchOpts();

	for (const char *path : BG_SYSTEM_INCLUDES) {
		headerOpts.AddPath(llvm::StringRef(path), clang::frontend::System, false, false);
	}
}

bool BindgenFrontendAction::BeginInvocation(clang::CompilerInstance &ci) {
	addSystemIncludes(ci);
	return true;
}

bool BindgenFrontendAction::BeginSourceFileAction(clang::CompilerInstance &ci)
{
	clang::Preprocessor &preprocessor = ci.getPreprocessor();
	preprocessor.addPPCallbacks(std::make_unique<PreprocessorHandler>(this->m_document, preprocessor));
	return true;
}

std::unique_ptr<clang::ASTConsumer> BindgenFrontendAction::CreateASTConsumer(clang::CompilerInstance &ci, llvm::StringRef file) {
	return std::make_unique<BindgenASTConsumer>(this->m_document);
}
