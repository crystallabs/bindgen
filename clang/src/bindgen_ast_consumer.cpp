#include "common.hpp"
#include "bindgen_ast_consumer.hpp"

#include "clang/Parse/ParseAST.h"

#include "function_match_handler.hpp"
#include "record_match_handler.hpp"
#include "enum_match_handler.hpp"
#include "macro_ast_consumer.hpp"

static llvm::cl::list<std::string> ClassList("c", llvm::cl::desc("Classes to inspect"), llvm::cl::value_desc("class"));
static llvm::cl::list<std::string> EnumList("e", llvm::cl::desc("Enums to inspect"), llvm::cl::value_desc("enum"));

BindgenASTConsumer::BindgenASTConsumer(Document &doc, clang::CompilerInstance &compiler)
	: m_compiler(compiler), m_functionHandler(nullptr), m_document(doc), m_matchFinder(m_matchFinderOpts)
{
	using namespace clang::ast_matchers;

	for (const std::string &className : ClassList) {
		DeclarationMatcher classMatcher = cxxRecordDecl(isDefinition(), hasName(className)).bind("recordDecl");

		auto handler = make_unique<RecordMatchHandler>(m_document, className);
		this->m_matchFinder.addMatcher(classMatcher, handler.get());
		this->m_classHandlers.push_back(std::move(handler));
	}

	if (FunctionMatchHandler::isActive()) {
		DeclarationMatcher funcMatcher = functionDecl(unless(hasParent(cxxRecordDecl()))).bind("functionDecl");
		auto handler = make_unique<FunctionMatchHandler>(m_document);
		this->m_matchFinder.addMatcher(funcMatcher, handler.get());
		this->m_functionHandler = std::move(handler);
	}

	for (const std::string &enumName : EnumList) {
		DeclarationMatcher enumMatcher = enumDecl(hasName(enumName)).bind("enumDecl");
		DeclarationMatcher typedefMatcher = typedefNameDecl(hasName(enumName)).bind("typedefNameDecl");

		auto handler = make_unique<EnumMatchHandler>(m_document, enumName);
		this->m_matchFinder.addMatcher(enumMatcher, handler.get());
		this->m_matchFinder.addMatcher(typedefMatcher, handler.get());
		this->m_enumHandlers.push_back(std::move(handler));
	}
}

BindgenASTConsumer::~BindgenASTConsumer() {
}

void BindgenASTConsumer::HandleTranslationUnit(clang::ASTContext &ctx) {
	this->m_matchFinder.matchAST(ctx);
  // FIXME: clang segfaults in 6 or newer when calling ParseAST in destructor
	this->evaluateMacros(ctx);
	this->serializeAndOutput();
}

static std::string buildMacroEvaluationFile(const std::vector<Macro> &macros) {
	std::string backBuffer;
	llvm::raw_string_ostream stream(backBuffer);

	for (const Macro &macro : macros) {
		if (!macro.isFunction) {
			stream << "auto bg_macro_val_" << macro.name << " = (" << macro.name << ");\n";
		}
	}

	return stream.str();
}

void BindgenASTConsumer::evaluateMacros(clang::ASTContext &ctx) {
	clang::SourceManager &sourceMgr = this->m_compiler.getSourceManager();
	MacroAstConsumer *consumer = new MacroAstConsumer(this->m_document.macros);
	std::string evalFile = buildMacroEvaluationFile(this->m_document.macros);

	clang::FileID macroFile = sourceMgr.createFileID(llvm::MemoryBuffer::getMemBuffer(evalFile));
	sourceMgr.setMainFileID(macroFile);

	this->m_compiler.getDiagnostics().setClient(new clang::IgnoringDiagConsumer());
	clang::ParseAST(this->m_compiler.getPreprocessor(), consumer, ctx);
}

void BindgenASTConsumer::serializeAndOutput() {
	JsonStream stream(std::cout);
	stream << this->m_document;
	std::cout << std::endl;

	// FIXME: Currently the process crashes during clang's Parser destructor. This is a workaround.
	exit(0);
}
