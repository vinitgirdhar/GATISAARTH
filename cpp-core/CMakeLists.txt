cmake_minimum_required(VERSION 3.14)
project(cpp_core VERSION 1.1.0 LANGUAGES CXX C)

# scripts/build_cpp.sh runs a bare `cmake ..`; make that a Release build.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(GATI_BUILD_TOOLS "Build replay_external_imu and bench_200hz" ON)
option(GATI_BUILD_TESTS "Build the ctest suite" ON)
option(GATI_ASAN "Build with AddressSanitizer (MSVC /fsanitize=address, GCC/Clang -fsanitize=address)" OFF)

# The original file required Eigen3, which no source uses; it is gone, so a clean
# machine no longer fails at configure time.
find_package(Threads REQUIRED)

# Only src/engine is built: it is the whole engine (the NavEngine ES-EKF, the edge
# pipeline, replay and the synthetic drive). Nothing else under src/ is compiled.
file(GLOB ENGINE_SOURCES CONFIGURE_DEPENDS "src/engine/*.cpp")

add_library(gati_engine STATIC ${ENGINE_SOURCES})
target_include_directories(gati_engine PUBLIC include)
target_link_libraries(gati_engine PUBLIC Threads::Threads)
if(WIN32)
  target_link_libraries(gati_engine PUBLIC ws2_32)   # UdpLineBuf
endif()

if(MSVC)
  target_compile_options(gati_engine PRIVATE /W4 /permissive-)
  set(GATI_TOOL_WARNINGS /W4 /permissive-)
  if(GATI_ASAN)
    target_compile_options(gati_engine PRIVATE /fsanitize=address)
  endif()
else()
  target_compile_options(gati_engine PRIVATE -Wall -Wextra -Wpedantic)
  set(GATI_TOOL_WARNINGS -Wall -Wextra -Wpedantic)
  if(GATI_ASAN)
    target_compile_options(gati_engine PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address,undefined)
  endif()
endif()

if(GATI_BUILD_TOOLS)
  foreach(tool replay_external_imu bench_200hz)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools/${tool}.cpp")
      add_executable(${tool} tools/${tool}.cpp)
      target_link_libraries(${tool} PRIVATE gati_engine)
      target_compile_options(${tool} PRIVATE ${GATI_TOOL_WARNINGS})
      if(GATI_ASAN AND MSVC)
        target_compile_options(${tool} PRIVATE /fsanitize=address)
      endif()
    endif()
  endforeach()
  if(TARGET bench_200hz)
    target_compile_definitions(bench_200hz PRIVATE
      GATI_BUILD_CONFIG="$<CONFIG>"
      GATI_CXX_FLAGS="${CMAKE_CXX_FLAGS} ${CMAKE_CXX_FLAGS_RELEASE}")
  endif()
endif()

if(GATI_BUILD_TESTS)
  enable_testing()
  file(GLOB TEST_SOURCES CONFIGURE_DEPENDS "tests/test_*.cpp")
  foreach(src ${TEST_SOURCES})
    get_filename_component(name ${src} NAME_WE)
    add_executable(${name} ${src})
    target_link_libraries(${name} PRIVATE gati_engine)
    target_compile_options(${name} PRIVATE ${GATI_TOOL_WARNINGS})
    if(GATI_ASAN AND MSVC)
      target_compile_options(${name} PRIVATE /fsanitize=address)
    endif()
    add_test(NAME ${name} COMMAND ${name})
    set_tests_properties(${name} PROPERTIES TIMEOUT 120)
  endforeach()
  if(TARGET bench_200hz)
    add_test(NAME bench_smoke COMMAND bench_200hz --smoke)
    set_tests_properties(bench_smoke PROPERTIES TIMEOUT 10)
  endif()
endif()

message(STATUS "cpp_core ${PROJECT_VERSION}: C++17, ${CMAKE_BUILD_TYPE}${CMAKE_CONFIGURATION_TYPES}, tools=${GATI_BUILD_TOOLS}, tests=${GATI_BUILD_TESTS}")
