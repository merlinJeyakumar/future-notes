# Only our native runner is rebuilt; do not claim these switches recompile or
# harden prebuilt Flutter, media, PDF or Office DLLs. Debug remains debuggable.
function(apply_process_hardening target)
  if(NOT MSVC)
    message(FATAL_ERROR "Windows process hardening requires the MSVC toolchain.")
  endif()
  target_compile_definitions(${target} PRIVATE
    "$<$<CONFIG:Release>:FN_RELEASE_HARDENING=1>")
  target_compile_options(${target} PRIVATE
    "$<$<CONFIG:Release>:/GS;/guard:cf>")
  target_link_options(${target} PRIVATE
    "$<$<CONFIG:Release>:/DYNAMICBASE;/HIGHENTROPYVA;/NXCOMPAT;/GUARD:CF;/DEPENDENTLOADFLAG:0xA00>")
endfunction()
