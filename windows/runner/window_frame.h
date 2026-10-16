#ifndef FUTURE_NOTES_WINDOW_FRAME_H_
#define FUTURE_NOTES_WINDOW_FRAME_H_
#include <windows.h>
#include <commctrl.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include <optional>

class WindowFrame {
 public:
  WindowFrame(HWND window, HWND child, flutter::BinaryMessenger* messenger);
  ~WindowFrame();
  std::optional<LRESULT> Handle(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  bool Configure(bool enabled);
  LRESULT HitTest(LPARAM point) const;
  flutter::EncodableValue State() const;
  void NotifyState();
  static LRESULT CALLBACK ChildProc(HWND child, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR id, DWORD_PTR owner);
  HWND window_;
  HWND child_;
  bool enabled_ = false;
  bool subclassed_ = false;
  bool last_maximized_ = false;
  bool last_minimized_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
