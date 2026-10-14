cmake_minimum_required(VERSION 3.5.1 FATAL_ERROR)
project(parser-clang)

include(crystal.cmake)

######################
# Configure sources
######################

# Setup sources
include_directories(${PROJECT_SOURCE_DIR}/src)
include_directories(${PROJECT_SOURCE_DIR}/include)

file(GLOB source_files "${PROJECT_SOURCE_DIR}/src/*.cpp")
add_executable(parser ${source_files})

# bindgen looks for the tool next to its sources, wherever it was built.
set_target_properties(parser PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${PROJECT_SOURCE_DIR})

# Link against clang libraries
target_link_libraries(parser ${clang_libs})
if ("${CMAKE_BUILD_TYPE}" STREQUAL "Debug")
  message(STATUS "CLang Libs: ${clang_libs}")
endif()

# Link against LLVM libraries
target_link_libraries(parser ${llvm_libs})

# Look up the libraries LLVM depends on, as they may be outside the linker's
# default search paths (e.g. Homebrew on macOS)
foreach (lib ${system_libs})
  if ("${lib}" MATCHES "^-l(.+)$")
    find_library(system_lib_${CMAKE_MATCH_1} NAMES ${CMAKE_MATCH_1})
    if (system_lib_${CMAKE_MATCH_1})
      set(lib ${system_lib_${CMAKE_MATCH_1}})
    endif ()
  endif ()
  target_link_libraries(parser ${lib})
endforeach ()

# Static LLVM libraries may contain bitcode (e.g. some Homebrew bottles), which
# only LLVM's own libLTO can read, not the one of Apple's linker
if (APPLE AND EXISTS "${LLVM_LIBRARY_DIRS}/libLTO.dylib")
  target_link_libraries(parser "-Wl,-lto_library,${LLVM_LIBRARY_DIRS}/libLTO.dylib")
endif ()

if ("${CMAKE_BUILD_TYPE}" STREQUAL "Debug")
  message(STATUS "LLVM Libs: ${llvm_libs}")
endif ()

message(STATUS "CMake System Name: ${CMAKE_SYSTEM_NAME}")

# Enable threads
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
target_link_libraries(parser Threads::Threads)

# PCRE2 may live outside the default search paths (e.g. Homebrew on macOS)
find_path(pcre2_include_dir pcre2.h)
find_library(pcre2_library pcre2-8 HINTS ${pcre2_include_dir}/../lib)
if (NOT pcre2_include_dir OR NOT pcre2_library)
  message(FATAL_ERROR "PCRE2 not found")
endif ()

target_include_directories(parser PRIVATE ${pcre2_include_dir})
target_link_libraries(parser ${pcre2_library})
