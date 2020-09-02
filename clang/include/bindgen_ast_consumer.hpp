#ifndef BINDGEN_AST_CONSUMER_HPP
#define BINDGEN_AST_CONSUMER_HPP

class RecordMatchHandler;
class EnumMatchHandler;
class FunctionMatchHandler;

class BindgenASTConsumer : public clang::ASTConsumer {
public:
	BindgenASTConsumer(Document &doc, clang::CompilerInstance &compiler);

	~BindgenASTConsumer() override;

	void HandleTranslationUnit(clang::ASTContext &ctx) override;

private:

	void evaluateMacros(clang::ASTContext &ctx);
	void serializeAndOutput();

	clang::CompilerInstance &m_compiler;
	std::vector<std::unique_ptr<RecordMatchHandler>> m_classHandlers;
	std::vector<std::unique_ptr<EnumMatchHandler>> m_enumHandlers;
	std::unique_ptr<FunctionMatchHandler> m_functionHandler;
	Document &m_document;
	clang::ast_matchers::MatchFinder::MatchFinderOptions m_matchFinderOpts;
	clang::ast_matchers::MatchFinder m_matchFinder;
};

#endif // BINDGEN_AST_CONSUMER_HPP
