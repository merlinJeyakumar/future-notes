#ifndef FUTURE_NOTES_DESKTOP_ACTIONS_H_
#define FUTURE_NOTES_DESKTOP_ACTIONS_H_
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <flutter/binary_messenger.h>
#include <windows.h>
#include <memory>
#include <string>

class DesktopActions {
 public:
  DesktopActions(HWND window, flutter::BinaryMessenger* messenger);
  ~DesktopActions();
 private:
  std::wstring CacheRoot(const std::wstring& validation_root = {});
  std::wstring cache_root_;
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
