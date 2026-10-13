#ifndef COMMON_HPP
#define COMMON_HPP

#include "clang/Tooling/CommonOptionsParser.h"
#include "clang/ASTMatchers/ASTMatchFinder.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/FrontendActions.h"
#include "clang/ASTMatchers/ASTMatchers.h"
#include "clang/AST/ASTConsumer.h"
#include "clang/Tooling/Tooling.h"
#include "clang/AST/ASTContext.h"
#include "clang/Basic/Version.h"
#include "clang/AST/APValue.h"
#include "clang/AST/AST.h"
#include <iostream>
#include <sstream>
#include <utility>
#include <vector>
#include <map>

#include "helper.hpp"
#include "structures.hpp"

#endif // COMMON_HPP
