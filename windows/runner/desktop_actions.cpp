#include "desktop_actions.h"
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shlobj.h>
#include <sddl.h>
#include <aclapi.h>
#include <vector>
#include <cwchar>
namespace {
std::wstring Wide(const std::string& text) {
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring value(size, L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), value.data(), size)) return {};
  return value;
}
std::string Utf8(const std::wstring& text) {
  int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string value(size, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), value.data(), size, nullptr, nullptr);
  return value;
}
bool RegularPath(const std::wstring& path) {
  for (size_t end = 3; end <= path.size(); ++end) {
    if (end != path.size() && path[end] != L'\\') continue;
    DWORD attributes = GetFileAttributesW(path.substr(0, end).c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
  }
  return true;
}
}
DesktopActions::DesktopActions(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger, "future_notes/desktop", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "cacheRoot") {
      const auto* validation = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      auto root = CacheRoot(validation ? Wide(*validation) : std::wstring());
      cache_root_ = root;
      if (root.empty()) result->Error("cache", "Private cache unavailable.");
      else result->Success(flutter::EncodableValue(Utf8(root)));
    } else if (call.method_name() == "openFile") {
      const auto* value = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      auto root = cache_root_;
      auto path = value ? Wide(*value) : std::wstring();
      const auto prefix = root + L"\\";
      if (root.empty() || path.size() <= prefix.size() || _wcsnicmp(prefix.c_str(), path.c_str(), prefix.size()) != 0 || path.find(L"..") != std::wstring::npos || !RegularPath(path)) {
        result->Error("file", "Completed cache file required."); return;
      }
      DWORD attr = GetFileAttributesW(path.c_str());
      if (attr == INVALID_FILE_ATTRIBUTES || (attr & FILE_ATTRIBUTE_DIRECTORY)) { result->Error("file", "Cache file unavailable."); return; }
      SHELLEXECUTEINFOW execute{};
      execute.cbSize = sizeof(execute); execute.fMask = SEE_MASK_FLAG_NO_UI;
      execute.hwnd = window_; execute.lpVerb = L"open"; execute.lpFile = path.c_str(); execute.nShow = SW_SHOWNORMAL;
      if (!ShellExecuteExW(&execute)) result->Error("association", "No available system application.");
      else result->Success();
    } else result->NotImplemented();
  });
}
DesktopActions::~DesktopActions() {
  channel_->SetMethodCallHandler(nullptr);
}
std::wstring DesktopActions::CacheRoot(const std::wstring& validation_root) {
  PWSTR location = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &location))) return {};
  std::wstring base(location); CoTaskMemFree(location);
  if (!RegularPath(base)) return {};
  auto parent = base + L"\\FutureNotes";
  if (!validation_root.empty()) {
    const auto last = validation_root.find_last_of(L"\\/");
    const auto name = validation_root.substr(last == std::wstring::npos ? 0 : last + 1);
    if (name.rfind(L"future-notes-validation-", 0) != 0 || !RegularPath(validation_root)) return {};
    parent = validation_root;
  }
  if (!CreateDirectoryW(parent.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return {};
  if (!RegularPath(parent)) return {};
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};
  DWORD size = 0; GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> buffer(size);
  bool ok = GetTokenInformation(token, TokenUser, buffer.data(), size, &size) != FALSE;
  CloseHandle(token); if (!ok) return {};
  LPWSTR sid = nullptr;
  if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid, &sid)) return {};
  std::wstring sddl = L"D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;" + std::wstring(sid) + L")"; LocalFree(sid);
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1, &descriptor, nullptr)) return {};
  SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), descriptor, FALSE};
  auto root = parent + L"\\AttachmentCache";
  bool created = CreateDirectoryW(root.c_str(), &attributes) != FALSE || GetLastError() == ERROR_ALREADY_EXISTS;
  PACL acl = nullptr; BOOL present = FALSE, defaulted = FALSE;
  bool secured = created && RegularPath(root) && GetSecurityDescriptorDacl(descriptor, &present, &acl, &defaulted) && present &&
    SetNamedSecurityInfoW(root.data(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, nullptr, nullptr, acl, nullptr) == ERROR_SUCCESS;
  LocalFree(descriptor);
  return secured ? root : std::wstring();
}
