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

if ("${CMAKE_BUILD_TYPE}" STREQUAL "Debug")
  message(STATUS "LLVM Libs: ${llvm_libs}")
endif ()

message(STATUS "CMake System Name: ${CMAKE_SYSTEM_NAME}")

if ("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
  include_directories(/usr/local/include)
  include_directories(/usr/local/opt/libevent/include)

endif ()

# Enable threads
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
target_link_libraries(parser Threads::Threads)

target_link_libraries(parser pcre2-8)
