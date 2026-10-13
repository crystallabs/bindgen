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

# Execute find_clang.cr
message(STATUS "Run: crystal find_clang.cr -- --clang ${llvm_clang_bin} --llvm-config ${LLVM_CONFIG} --quiet")

execute_process(
        COMMAND ${crystal_bin} ${PROJECT_SOURCE_DIR}/find_clang.cr -- --clang ${llvm_clang_bin} --llvm-config ${LLVM_CONFIG} --quiet
        # COMMAND_ECHO STDOUT
        ERROR_VARIABLE find_clang_error
)

if(NOT ${find_clang_error} STREQUAL "")
  message(FATAL_ERROR ${find_clang_error})
endif()

# Execute find_clang.cr for clang_libs
message(STATUS "Run: crystal find_clang.cr -- --print-clang-libs --clang ${llvm_clang_bin} --llvm-config ${LLVM_CONFIG} --quiet")
execute_process(
        COMMAND ${crystal_bin} ${PROJECT_SOURCE_DIR}/find_clang.cr -- --print-clang-libs --clang ${llvm_clang_bin} --llvm-config ${LLVM_CONFIG} --quiet
        # COMMAND_ECHO STDOUT
        OUTPUT_VARIABLE clang_libs
        ERROR_VARIABLE find_clang_error
)
if(NOT ${find_clang_error} STREQUAL "")
  message(FATAL_ERROR ${find_clang_error})
endif()

# Execute find_clang.cr for llvm_libs
message(STATUS "Run: crystal find_clang.cr -- --print-llvm-libs --clang ${llvm_clang_bin} --llvm-config ${LLVM_CONFIG} --quiet")
execute_process(
        COMMAND ${crystal_bin} ${PROJECT_SOURCE_DIR}/find_clang.cr -- --print-llvm-libs --clang ${llvm_clang_bin} --llvm-config ${LLVM_CONFIG} --quiet
        # COMMAND_ECHO STDOUT
        # ERROR_VARIABLE find_clang_error
        OUTPUT_VARIABLE llvm_libs
        OUTPUT_STRIP_TRAILING_WHITESPACE
)

if("${llvm_libs}" STREQUAL "")
  message(WARNING "Unable to find llvm libs. Will run command manually" )

  # NOTE: This execute_process will use `llvm-config --libs all` to gather the libs
  message(STATUS "Run: ${llvm_config_bin} --libs all")
  execute_process(
          COMMAND bash -c "${llvm_config_bin} --libs all | sed -E 's/\\-l/;/g' | sed -E 's/ //g'"
          # COMMAND_ECHO STDOUT
          # ERROR_VARIABLE find_clang_error
          OUTPUT_VARIABLE llvm_libs
          OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  # Find the libraries that correspond to the LLVM components
  # that we wish to use
  # llvm_map_components_to_libnames(llvm_libs all)

endif()
# message(STATUS "llvm_libs: ${llvm_libs}")