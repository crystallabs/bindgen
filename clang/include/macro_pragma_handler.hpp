#ifndef MACRO_PRAGMA_HANDLER_HPP
#define MACRO_PRAGMA_HANDLER_HPP

#include "clang/Lex/Pragma.h"
#include "structures.hpp"
#include <vector>

// Evaluates the macros found by `PreprocessorHandler` in the same parsing
// pass.  `appendPragma()` ends the main file in `#pragma bindgen
// evaluate_macros`, which then enters a buffer defining a variable per macro
// to evaluate.  Their values are read by `MacroAstConsumer`.
class MacroPragmaHandler : public clang::PragmaHandler {
public:
	// Evaluates the macros in *macros* starting at index *first*.
	MacroPragmaHandler(const std::vector<Macro> &macros, size_t first);

	// Appends the pragma to the main *file* of *ci*.
	static void appendPragma(clang::CompilerInstance &ci, llvm::StringRef file);

	void HandlePragma(clang::Preprocessor &pp, clang::PragmaIntroducer introducer, clang::Token &token) override;

private:
	// Builds the source with a variable definition per macro to evaluate.
	std::string evaluationFile(clang::Preprocessor &pp) const;

	const std::vector<Macro> &m_macros;
	size_t m_first;
	bool m_suppressedDiagnostics;
};

#endif // MACRO_PRAGMA_HANDLER_HPP
