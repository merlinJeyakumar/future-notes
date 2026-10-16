#include "process_hardening.h"

ProcessHardeningResult ApplyProcessHardening() {
  // Exclude the current directory and PATH, including before plugin loading.
  // All bundled native dependencies live beside the executable. Explicit
  // absolute library loads still work; this is not a DLL signature allowlist.
  if (!SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_APPLICATION_DIR |
                                LOAD_LIBRARY_SEARCH_SYSTEM32)) {
    return {"dll_search", GetLastError()};
  }

  PROCESS_MITIGATION_IMAGE_LOAD_POLICY images = {};
  if (!GetProcessMitigationPolicy(GetCurrentProcess(), ProcessImageLoadPolicy,
                                  &images, sizeof(images))) {
    return {"read_image_policy", GetLastError()};
  }
  images.NoRemoteImages = 1;
  images.NoLowMandatoryLabelImages = 1;
  images.PreferSystem32Images = 1;
  if (!SetProcessMitigationPolicy(ProcessImageLoadPolicy, &images,
                                  sizeof(images))) {
    return {"image_policy", GetLastError()};
  }

  PROCESS_MITIGATION_EXTENSION_POINT_DISABLE_POLICY extensions = {};
  extensions.DisableExtensionPoints = 1;
  if (!SetProcessMitigationPolicy(ProcessExtensionPointDisablePolicy,
                                  &extensions, sizeof(extensions))) {
    return {"extension_points", GetLastError()};
  }

  PROCESS_MITIGATION_STRICT_HANDLE_CHECK_POLICY handles = {};
  handles.RaiseExceptionOnInvalidHandleReference = 1;
  handles.HandleExceptionsPermanentlyEnabled = 1;
  if (!SetProcessMitigationPolicy(ProcessStrictHandleCheckPolicy, &handles,
                                  sizeof(handles))) {
    return {"strict_handles", GetLastError()};
  }
  // Do not prohibit dynamic code or require Microsoft-signed images: Flutter
  // executable mappings/trampolines and bundled third-party DLLs need them.
  return {nullptr, ERROR_SUCCESS};
}
