#include "common.hpp"
#include "json_stream.hpp"

#include "bindgen_frontend_action.hpp"
#include "macro_frontend_action.hpp"

static llvm::cl::OptionCategory BindgenCategory("bindgen options");
// See bindgen_ast_consumer.cpp for more

// Creates `Action`s operating on a shared `Document`.
template< typename Action >
class ActionFactory : public clang::tooling::FrontendActionFactory {
public:
	ActionFactory(Document &doc) : m_document(doc) { }

	std::unique_ptr<clang::FrontendAction> create() override {
		return std::make_unique<Action>(this->m_document);
	}

private:
	Document &m_document;
};

// Evaluates the macros in *doc*.  Not all macros expand to an expression, so
// errors are expected and ignored.
static void evaluateMacros(Document &doc, clang::tooling::CommonOptionsParser &op) {
	std::string path = clang::tooling::getAbsolutePath("bindgen_macro_evaluation.cpp");
	std::string source = MacroFrontendAction::evaluationFile(doc, op.getSourcePathList());
	clang::IgnoringDiagConsumer diagnostics;

	clang::tooling::ClangTool tool(op.getCompilations(), { path });
	tool.mapVirtualFile(path, source);
	tool.setDiagnosticConsumer(&diagnostics);
	tool.appendArgumentsAdjuster(clang::tooling::getInsertArgumentAdjuster(
		"-ferror-limit=0", clang::tooling::ArgumentInsertPosition::END));

	ActionFactory<MacroFrontendAction> factory(doc);
	tool.run(&factory);
}

int main(int argc, const char **argv) {
	auto op = clang::tooling::CommonOptionsParser::create(argc, argv, BindgenCategory);
	if (!op) {
		llvm::errs() << llvm::toString(op.takeError()) << "\n";
		return 1;
	}

	Document doc;
	clang::tooling::ClangTool tool(op->getCompilations(), op->getSourcePathList());
	ActionFactory<BindgenFrontendAction> factory(doc);

	if (int result = tool.run(&factory)) {
		return result;
	}

	if (MacroFrontendAction::isActive(doc)) {
		evaluateMacros(doc, *op);
	}

	JsonStream stream(std::cout);
	stream << doc;
	std::cout << std::endl;

	return 0;
}
