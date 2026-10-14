#include "common.hpp"
#include "macro_pragma_handler.hpp"

#include "clang/Lex/Preprocessor.h"
#include "clang/Lex/PreprocessorOptions.h"
#include "clang/Lex/MacroInfo.h"

#include <algorithm>

MacroPragmaHandler::MacroPragmaHandler(const std::vector<Macro> &macros, size_t first)
	: clang::PragmaHandler("bindgen"), m_macros(macros), m_first(first), m_suppressedDiagnostics(false)
{
}

void MacroPragmaHandler::appendPragma(clang::CompilerInstance &ci, llvm::StringRef file) {
	if (file == "-") return; // Can't read standard input twice.

	auto buffer = ci.getFileManager().getBufferForFile(file);
	if (!buffer) return; // Reported by Clang when it opens the file.

	std::string source = (*buffer)->getBuffer().str();
	source += "\n#pragma bindgen evaluate_macros\n";

	// The preprocessor takes ownership of the buffer.
	ci.getPreprocessorOpts().addRemappedFile(file, llvm::MemoryBuffer::getMemBufferCopy(source, file).release());
}

// Walks the tokens of *info*, and of the macros it uses, keeping the brackets
// to close in *open*.  Returns false if a bracket doesn't match.
static bool nestsBrackets(clang::Preprocessor &pp, const clang::MacroInfo *info,
	std::vector<clang::tok::TokenKind> &open, std::vector<const clang::MacroInfo *> &active) {
	if (std::find(active.begin(), active.end(), info) != active.end()) {
		return true; // Not expanded recursively
	}

	active.push_back(info);

	for (const clang::Token &token : info->tokens()) {
		switch (token.getKind()) {
		case clang::tok::l_paren: open.push_back(clang::tok::r_paren); break;
		case clang::tok::l_square: open.push_back(clang::tok::r_square); break;
		case clang::tok::l_brace: open.push_back(clang::tok::r_brace); break;
		case clang::tok::r_paren:
		case clang::tok::r_square:
		case clang::tok::r_brace:
			if (open.empty() || open.back() != token.getKind()) return false;
			open.pop_back();
			break;
		default:
			if (const clang::IdentifierInfo *identifier = token.getIdentifierInfo()) {
				const clang::MacroInfo *used = pp.getMacroInfo(identifier);
				if (used && !nestsBrackets(pp, used, open, active)) return false;
			}
		}
	}

	active.pop_back();
	return true;
}

// Does the macro *name* expand to properly nested brackets?
static bool nestsBrackets(clang::Preprocessor &pp, const std::string &name) {
	const clang::MacroInfo *info = pp.getMacroInfo(pp.getIdentifierInfo(name));
	if (!info) return true; // Undefined again

	std::vector<clang::tok::TokenKind> open;
	std::vector<const clang::MacroInfo *> active;
	return nestsBrackets(pp, info, open, active) && open.empty();
}

std::string MacroPragmaHandler::evaluationFile(clang::Preprocessor &pp) const {
	std::string buffer;
	llvm::raw_string_ostream stream(buffer);
	bool empty = true;

	for (size_t i = this->m_first; i < this->m_macros.size(); i++) {
		const Macro &macro = this->m_macros[i];
		if (macro.isFunction) continue;

		// A macro with unbalanced brackets isn't an expression, but would
		// derail parsing the following definitions.  It's left out, failing
		// like other non-expressions.
		std::string expression = nestsBrackets(pp, macro.name) ? macro.name : "";
		stream << "auto bg_macro_val_" << macro.name << " = (" << expression << ");\n";
		empty = false;
	}

	if (empty) return "";

	// Diagnostics are back on once the parser reads past the last definition.
	stream << "#pragma bindgen end_evaluation\n";
	return stream.str();
}

void MacroPragmaHandler::HandlePragma(clang::Preprocessor &pp, clang::PragmaIntroducer introducer, clang::Token &token) {
	pp.LexUnexpandedToken(token);
	std::string command = token.is(clang::tok::identifier) ? token.getIdentifierInfo()->getName().str() : "";

	while (token.isNot(clang::tok::eod)) {
		pp.LexUnexpandedToken(token);
	}

	clang::DiagnosticsEngine &diagnostics = pp.getDiagnostics();

	if (command == "end_evaluation") {
		diagnostics.setSuppressAllDiagnostics(this->m_suppressedDiagnostics);
		return;
	} else if (command != "evaluate_macros") {
		return;
	}

	std::string source = evaluationFile(pp);
	if (source.empty()) return;

	// Not all macros expand to an expression, so errors are expected.  These
	// are ignored without counting towards the error limit.
	this->m_suppressedDiagnostics = diagnostics.getSuppressAllDiagnostics();
	diagnostics.setSuppressAllDiagnostics(true);

	std::string path = clang::tooling::getAbsolutePath("bindgen_macro_evaluation.cpp");
	clang::FileID file = pp.getSourceManager().createFileID(llvm::MemoryBuffer::getMemBufferCopy(source, path));
	pp.EnterSourceFile(file, nullptr, introducer.Loc);
}
