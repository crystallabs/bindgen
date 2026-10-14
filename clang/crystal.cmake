include(llvm.cmake)

######################
# Gather info
######################

# Find crystal bin
if(NOT EXISTS ${crystal_bin})
  find_program(crystal_bin crystal)
  message(STATUS "Found crystal exec: ${crystal_bin}")
endif()

if(NOT EXISTS ${shards_bin})
  find_program(shards_bin shards)
  message(STATUS "Found shards exec: ${shards_bin}")
endif()

# Execute find_clang.cr.  It writes include/generated.hpp, variables.yml,
# the spec configuration and variables.cmake, which sets `clang_libs` and
# `llvm_libs`.  Its diagnostics go to standard error.
message(STATUS "Run: crystal find_clang.cr -- --clang ${llvm_clang_bin} --llvm-config ${LLVM_CONFIG}")

execute_process(
        COMMAND ${crystal_bin} ${PROJECT_SOURCE_DIR}/find_clang.cr -- --clang ${llvm_clang_bin} --llvm-config ${LLVM_CONFIG}
        RESULT_VARIABLE find_clang_result
)

if(NOT "${find_clang_result}" STREQUAL "0")
  message(FATAL_ERROR "find_clang.cr failed: ${find_clang_result}")
endif()

include(${PROJECT_SOURCE_DIR}/variables.cmake)
