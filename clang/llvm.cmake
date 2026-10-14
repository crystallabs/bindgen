######################
# LLVM Setup
######################
# Search for LLVM.  Homebrew doesn't link its LLVM into the default prefix.
if(APPLE AND NOT LLVM_DIR)
  execute_process(
    COMMAND brew --prefix llvm
    OUTPUT_VARIABLE brew_llvm_prefix
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )
  if(brew_llvm_prefix)
    list(APPEND CMAKE_PREFIX_PATH ${brew_llvm_prefix})
  endif()
endif()

find_package(LLVM REQUIRED CONFIG)

message(STATUS "Found LLVM: ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")
string(REGEX MATCH "^([0-9]+)" LLVM_VER ${LLVM_PACKAGE_VERSION})
message(STATUS "LLVM Major version: ${LLVM_VER}")

if(LLVM_VER LESS 14)
  message(FATAL_ERROR "LLVM 14 or newer is required, found ${LLVM_PACKAGE_VERSION}")
endif()

# LLVM 16+ headers require C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find the LLVM clang++ path
message(STATUS "LLVM Tools Dir: ${LLVM_TOOLS_BINARY_DIR}")

# The tool itself is built by the default C++ compiler.  This clang++ is
# queried for its search paths, and builds the C++ code in the specs.
find_program(llvm_clang_bin NAMES "clang++" PATHS ${LLVM_TOOLS_BINARY_DIR} NO_DEFAULT_PATH REQUIRED)
message(STATUS "Found clang++ exec: ${llvm_clang_bin}")

# Find llvm-config bin
find_program(llvm_config_bin NAMES "llvm-config" PATHS ${LLVM_TOOLS_BINARY_DIR} NO_DEFAULT_PATH REQUIRED)
message(STATUS "Found llvm-config bin: ${llvm_config_bin}")
set(LLVM_CONFIG ${llvm_config_bin})
message(STATUS "Using llvm-config exec: ${LLVM_CONFIG}")

# Include LLVM dirs
message(STATUS "Include LLVM dirs: ${LLVM_INCLUDE_DIRS}")
include_directories(${LLVM_INCLUDE_DIRS})

message(STATUS "Add LLVM definitions: ${LLVM_DEFINITIONS}")
add_definitions(${LLVM_DEFINITIONS})

# Clang doesn't necessarily search its own library directory
link_directories(${LLVM_LIBRARY_DIRS})
