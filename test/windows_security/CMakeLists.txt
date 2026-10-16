cmake_minimum_required(VERSION 3.14)
project(future_notes_security_tests LANGUAGES CXX)
enable_testing()
include("../../windows/runner/process_hardening.cmake")
add_executable(process_hardening_test
  process_hardening_test.cpp ../../windows/runner/process_hardening.cpp)
target_compile_features(process_hardening_test PRIVATE cxx_std_17)
target_compile_options(process_hardening_test PRIVATE /W4 /WX /GS)
target_compile_definitions(process_hardening_test PRIVATE UNICODE _UNICODE NOMINMAX)
target_include_directories(process_hardening_test PRIVATE ../../windows/runner)
target_link_libraries(process_hardening_test PRIVATE advapi32)
apply_process_hardening(process_hardening_test)
foreach(name search_probe low_probe)
  add_library(${name} SHARED harmless_probe.cpp)
  set_target_properties(${name} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fixtures")
endforeach()
add_test(NAME process_policies_and_dll_search COMMAND process_hardening_test
  "$<TARGET_FILE:search_probe>" "$<TARGET_FILE:low_probe>")
