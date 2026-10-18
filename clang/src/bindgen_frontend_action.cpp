#include "common.hpp"
#include "generated.hpp"

#include "bindgen_frontend_action.hpp"
#include "bindgen_ast_consumer.hpp"
#include "preprocessor_handler.hpp"
#include "macro_pragma_handler.hpp"
#include "macro_ast_consumer.hpp"

#include "clang/Lex/Preprocessor.h"
#include "clang/Frontend/MultiplexConsumer.h"

BindgenFrontendAction::BindgenFrontendAction(Document &doc)
	: m_document(doc), m_firstMacro(0)
{
}

void BindgenFrontendAction::addSystemIncludes(clang::CompilerInstance &ci) {
	clang::HeaderSearchOptions &headerOpts = ci.getHeaderSearchOpts();

	for (const char *path : BG_SYSTEM_INCLUDES) {
		// IgnoreSysRoot: these are absolute paths, not relative to a sysroot like macOS' SDK.
		headerOpts.AddPath(llvm::StringRef(path), clang::frontend::System, false, true);
	}
}

bool BindgenFrontendAction::BeginInvocation(clang::CompilerInstance &ci) {
	addSystemIncludes(ci);
	this->m_firstMacro = this->m_document.macros.size();

	if (PreprocessorHandler::isActive()) {
		MacroPragmaHandler::appendPragma(ci, getCurrentFile());
	}

	return true;
}

bool BindgenFrontendAction::BeginSourceFileAction(clang::CompilerInstance &ci)
{
	clang::Preprocessor &preprocessor = ci.getPreprocessor();
	preprocessor.addPPCallbacks(std::make_unique<PreprocessorHandler>(this->m_document, preprocessor));

	if (PreprocessorHandler::isActive()) {
		// The preprocessor takes ownership of the handler.
		preprocessor.AddPragmaHandler(new MacroPragmaHandler(this->m_document.macros, this->m_firstMacro));
	}

	return true;
}

std::unique_ptr<clang::ASTConsumer> BindgenFrontendAction::CreateASTConsumer(clang::CompilerInstance &ci, llvm::StringRef file) {
	std::vector<std::unique_ptr<clang::ASTConsumer>> consumers;
	consumers.push_back(std::make_unique<BindgenASTConsumer>(this->m_document));
	consumers.push_back(std::make_unique<MacroAstConsumer>(this->m_document.macros, this->m_firstMacro));

	return std::make_unique<clang::MultiplexConsumer>(std::move(consumers));
}
