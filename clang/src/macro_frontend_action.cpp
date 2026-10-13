#include "common.hpp"

#include "bindgen_frontend_action.hpp"
#include "macro_frontend_action.hpp"
#include "macro_ast_consumer.hpp"

MacroFrontendAction::MacroFrontendAction(Document &doc)
	: m_document(doc)
{
}

bool MacroFrontendAction::isActive(const Document &doc) {
	for (const Macro &macro : doc.macros) {
		if (!macro.isFunction) return true;
	}

	return false;
}

std::string MacroFrontendAction::evaluationFile(const Document &doc, const std::vector<std::string> &sources) {
	std::string buffer;
	llvm::raw_string_ostream stream(buffer);

	for (const std::string &source : sources) {
		stream << "#include \"" << clang::tooling::getAbsolutePath(source) << "\"\n";
	}

	for (const Macro &macro : doc.macros) {
		if (!macro.isFunction) {
			stream << "auto bg_macro_val_" << macro.name << " = (" << macro.name << ");\n";
		}
	}

	return stream.str();
}

bool MacroFrontendAction::BeginInvocation(clang::CompilerInstance &ci) {
	BindgenFrontendAction::addSystemIncludes(ci);
	return true;
}

std::unique_ptr<clang::ASTConsumer> MacroFrontendAction::CreateASTConsumer(clang::CompilerInstance &ci, llvm::StringRef file) {
	return std::make_unique<MacroAstConsumer>(this->m_document.macros);
}
