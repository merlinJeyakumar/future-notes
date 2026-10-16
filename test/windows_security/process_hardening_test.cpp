#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <cstdio>
#include <string>

#include "process_hardening.h"

namespace {
bool Check(bool condition, const char* description) {
  std::printf("%s: %s\n", condition ? "PASS" : "FAIL", description);
  return condition;
}

bool SetLowIntegrity(wchar_t* file) {
  // Workspace files can inherit Modify without WRITE_OWNER. Grant the owner
  // full control over this disposable fixture only, so Windows permits changing
  // its integrity label. No application or user-data ACL is changed by this test.
  PSECURITY_DESCRIPTOR original = nullptr;
  PSID owner = nullptr;
  PACL old_acl = nullptr;
  DWORD access_error = GetNamedSecurityInfoW(file, SE_FILE_OBJECT,
      OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, &owner, nullptr,
      &old_acl, nullptr, &original);
  if (access_error != ERROR_SUCCESS) return false;
  EXPLICIT_ACCESSW access = {};
  access.grfAccessPermissions = FILE_ALL_ACCESS;
  access.grfAccessMode = GRANT_ACCESS;
  access.grfInheritance = NO_INHERITANCE;
  access.Trustee.TrusteeForm = TRUSTEE_IS_SID;
  access.Trustee.TrusteeType = TRUSTEE_IS_USER;
  access.Trustee.ptstrName = static_cast<LPWSTR>(owner);
  PACL updated = nullptr;
  access_error = SetEntriesInAclW(1, &access, old_acl, &updated);
  if (access_error == ERROR_SUCCESS) {
    access_error = SetNamedSecurityInfoW(file, SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION, nullptr, nullptr, updated, nullptr);
  }
  if (updated) LocalFree(updated);
  LocalFree(original);
  if (access_error != ERROR_SUCCESS) {
    std::printf("Fixture owner grant failed: %lu\n", access_error);
    return false;
  }
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          L"S:(ML;;NW;;;LW)", SDDL_REVISION_1, &descriptor, nullptr)) {
    std::printf("Low integrity descriptor failed: %lu\n", GetLastError());
    return false;
  }
  PACL label = nullptr;
  BOOL present = FALSE;
  BOOL inherited = FALSE;
  const bool decoded = GetSecurityDescriptorSacl(descriptor, &present, &label,
                                                &inherited) && present;
  const DWORD error = decoded
      ? SetNamedSecurityInfoW(file, SE_FILE_OBJECT, LABEL_SECURITY_INFORMATION,
                             nullptr, nullptr, nullptr, label)
      : GetLastError();
  if (!decoded || error != ERROR_SUCCESS) {
    std::printf("Low integrity fixture label failed: %lu\n", error);
  }
  LocalFree(descriptor);
  return decoded && error == ERROR_SUCCESS;
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 3 && argc != 4) return 2;
  const auto result = ApplyProcessHardening();
  if (!result.ok()) {
    std::printf("FAIL: policy stage %s error %lu\n", result.failed_stage,
                result.error);
    return 1;
  }
  bool ok = true;
  PROCESS_MITIGATION_IMAGE_LOAD_POLICY images = {};
  ok &= Check(GetProcessMitigationPolicy(GetCurrentProcess(),
      ProcessImageLoadPolicy, &images, sizeof(images)) &&
      images.NoRemoteImages && images.NoLowMandatoryLabelImages &&
      images.PreferSystem32Images, "remote/low-integrity images blocked; system preferred");
  PROCESS_MITIGATION_EXTENSION_POINT_DISABLE_POLICY extensions = {};
  ok &= Check(GetProcessMitigationPolicy(GetCurrentProcess(),
      ProcessExtensionPointDisablePolicy, &extensions, sizeof(extensions)) &&
      extensions.DisableExtensionPoints, "legacy extension points disabled");
  PROCESS_MITIGATION_STRICT_HANDLE_CHECK_POLICY handles = {};
  ok &= Check(GetProcessMitigationPolicy(GetCurrentProcess(),
      ProcessStrictHandleCheckPolicy, &handles, sizeof(handles)) &&
      handles.RaiseExceptionOnInvalidHandleReference &&
      handles.HandleExceptionsPermanentlyEnabled, "strict handle checks permanent");
  PROCESS_MITIGATION_CONTROL_FLOW_GUARD_POLICY cfg = {};
  ok &= Check(GetProcessMitigationPolicy(GetCurrentProcess(),
      ProcessControlFlowGuardPolicy, &cfg, sizeof(cfg)) &&
      cfg.EnableControlFlowGuard, "runner Control Flow Guard enabled");

  const std::wstring fixture(argv[1]);
  const auto directory = fixture.substr(0, fixture.find_last_of(L"\\/"));
  const auto filename = fixture.substr(fixture.find_last_of(L"\\/") + 1);
  ok &= Check(SetCurrentDirectoryW(directory.c_str()) != FALSE,
              "synthetic working directory selected");
  ok &= Check(SetEnvironmentVariableW(L"PATH", directory.c_str()) != FALSE,
              "synthetic PATH selected");
  auto library = LoadLibraryW(filename.c_str());
  ok &= Check(library == nullptr, "DLL planted in current directory/PATH rejected");
  if (library) FreeLibrary(library);
  library = LoadLibraryW(fixture.c_str());
  ok &= Check(library != nullptr, "explicit trusted fixture path still loads");
  if (library) FreeLibrary(library);
  if (!Check(SetLowIntegrity(argv[2]), "synthetic DLL given low integrity label")) {
    return 1;
  }
  library = LoadLibraryW(argv[2]);
  ok &= Check(library == nullptr, "low-integrity DLL rejected even with absolute path");
  if (library) FreeLibrary(library);

  if (argc == 4) {
    // Real shipped imports, in a disposable test process. No engine entrypoint,
    // editor or storage is started and no user data is accessed.
    const std::wstring bundle(argv[3]);
    for (const wchar_t* name : {L"flutter_windows.dll", L"libmpv-2.dll",
                               L"pdfium.dll", L"office_oxide.dll"}) {
      library = LoadLibraryExW((bundle + L"/" + name).c_str(), nullptr,
          LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
      ok &= Check(library != nullptr, "bundled native library imports load under policies");
      if (library) FreeLibrary(library);
    }
  }
  return ok ? 0 : 1;
}
