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

  # for MacOS X or iOS, watchOS, tvOS (since 3.10.3)
  if (${LLVM_PACKAGE_VERSION} VERSION_GREATER "4")
    # Enable threads if LLVM over 4
    set(THREADS_PREFER_PTHREAD_FLAG ON)
    find_package(Threads REQUIRED)
    target_link_libraries(parser Threads::Threads)
  endif ()
elseif ("${CMAKE_SYSTEM_NAME}" STREQUAL "Linux")
  # Enable threads
  set(THREADS_PREFER_PTHREAD_FLAG ON)
  find_package(Threads REQUIRED)
  target_link_libraries(parser Threads::Threads)
endif ()

target_link_libraries(parser pcre2-8)
