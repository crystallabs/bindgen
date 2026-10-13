######################
# LLVM Setup
######################
set(LLVM_ENABLE_LIBCXX ON)

# Search for LLVM
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

find_program(llvm_clang_bin NAMES "clang++" PATHS ${LLVM_TOOLS_BINARY_DIR} NO_DEFAULT_PATH REQUIRED)
# message(STATUS "Found clang bin: ${llvm_clang_bin}")
set(CMAKE_CXX_COMPILER ${llvm_clang_bin})
message(STATUS "Using clang++ exec: ${CMAKE_CXX_COMPILER}")

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
