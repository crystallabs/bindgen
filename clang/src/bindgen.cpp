#include "common.hpp"
#include "json_stream.hpp"

#include "bindgen_frontend_action.hpp"

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

int main(int argc, const char **argv) {
	auto op = clang::tooling::CommonOptionsParser::create(argc, argv, BindgenCategory);
	if (!op) {
		llvm::errs() << llvm::toString(op.takeError()) << "\n";
		return 1;
	}

	Document doc;
	clang::tooling::ClangTool tool(op->getCompilations(), op->getSourcePathList());
	ActionFactory<BindgenFrontendAction> factory(doc);

	// Clang reports an error for any diagnostic in the sources.  Those are
	// still good to use as long as they could be parsed: The result then lacks
	// what was erroneous, which the user may not even be interested in.
	int result = tool.run(&factory);
	if (result != 0 && doc.translationUnits == 0) {
		return result;
	}

	if (!doc.errors.empty()) {
		for (const std::string &error : doc.errors) {
			llvm::errs() << "bindgen: error: " << error << "\n";
		}

		return 1;
	}

	JsonStream stream(std::cout);
	stream << doc;
	std::cout << std::endl;

	return 0;
}
