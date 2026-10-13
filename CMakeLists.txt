cmake_minimum_required(VERSION 3.5.1 FATAL_ERROR)
project(bindgen)

# To define a specific LLVM install set the path here:
# set(LLVM_DIR /usr/local/opt/llvm/lib/cmake/llvm)
# set(LLVM_DIR /usr/local/opt/llvm@7/lib/cmake/llvm)
# set(LLVM_DIR /usr/local/opt/llvm@9/lib/cmake/llvm)

add_subdirectory(clang)

# Find crystal bin
if(NOT EXISTS ${crystal_bin})
  find_program(crystal_bin crystal)
  message(STATUS "Found crystal exec: ${crystal_bin}")
endif()

if(NOT EXISTS ${shards_bin})
  find_program(shards_bin shards)
  message(STATUS "Found shards exec: ${shards_bin}")
endif()

add_custom_target(shards ALL
  COMMAND ${shards_bin} install
  WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
)

if(NOT EXISTS ${PROJECT_SOURCE_DIR}/bin)
  file(MAKE_DIRECTORY ${PROJECT_SOURCE_DIR}/bin)
endif()

add_custom_target(bindgen ALL
  COMMAND ${crystal_bin} build --release src/bindgen.cr --error-trace -o ${PROJECT_SOURCE_DIR}/bin/bindgen
  WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
  DEPENDS parser shards
)
