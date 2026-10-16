#include "window_frame.h"
#include <dwmapi.h>
#include <windowsx.h>
#include <flutter/standard_method_codec.h>

namespace {
constexpr UINT_PTR kFrameSubclass = 0x464E;
// Must match DesktopWindowFrame's logical-pixel layout.
constexpr int kCaptionHeight = 36;
constexpr int kControlsWidth = 3 * 46;
int Pixels(HWND window, int logical) {
  return MulDiv(logical, static_cast<int>(GetDpiForWindow(window)), 96);
}
}

WindowFrame::WindowFrame(HWND window, HWND child,
                         flutter::BinaryMessenger* messenger)
    : window_(window), child_(child) {
  subclassed_ = SetWindowSubclass(child_, ChildProc, kFrameSubclass,
                                 reinterpret_cast<DWORD_PTR>(this)) != FALSE;
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "future_notes/window", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "setFrame") {
      const auto* enabled = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!enabled || !Configure(*enabled)) {
        result->Error("frame", "Window frame could not be configured."); return;
      }
    } else if (call.method_name() == "minimize") {
      ShowWindow(window_, SW_MINIMIZE);
      if (!IsIconic(window_)) { result->Error("window", "Window could not be minimized."); return; }
    } else if (call.method_name() == "toggleMaximize") {
      const bool maximize = !IsZoomed(window_);
      ShowWindow(window_, maximize ? SW_MAXIMIZE : SW_RESTORE);
      if ((IsZoomed(window_) != FALSE) != maximize) { result->Error("window", "Window size could not be changed."); return; }
    } else if (call.method_name() == "close") {
      // WM_CLOSE follows Flutter's cancelable exit request and storage joins.
      if (!PostMessageW(window_, WM_CLOSE, 0, 0)) { result->Error("window", "Close request failed."); return; }
    } else { result->NotImplemented(); return; }
    result->Success(State());
  });
}

WindowFrame::~WindowFrame() {
  channel_->SetMethodCallHandler(nullptr);
  if (subclassed_ && IsWindow(child_)) RemoveWindowSubclass(child_, ChildProc, kFrameSubclass);
}

bool WindowFrame::Configure(bool enabled) {
  if (enabled && !subclassed_) return false;
  const bool previous = enabled_;
  enabled_ = enabled;
  const MARGINS margins = enabled ? MARGINS{1, 1, 1, 1} : MARGINS{0, 0, 0, 0};
  if (FAILED(DwmExtendFrameIntoClientArea(window_, &margins)) ||
      !SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)) {
    enabled_ = previous;
    const MARGINS old = previous ? MARGINS{1, 1, 1, 1} : MARGINS{0, 0, 0, 0};
    DwmExtendFrameIntoClientArea(window_, &old);
    SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    return false;
  }
  return true;
}

flutter::EncodableValue WindowFrame::State() const {
  return flutter::EncodableValue(flutter::EncodableMap{
    {flutter::EncodableValue("maximized"), flutter::EncodableValue(IsZoomed(window_) != FALSE)},
    {flutter::EncodableValue("minimized"), flutter::EncodableValue(IsIconic(window_) != FALSE)}});
}
void WindowFrame::NotifyState() {
  const bool maximized = IsZoomed(window_) != FALSE;
  const bool minimized = IsIconic(window_) != FALSE;
  if (maximized == last_maximized_ && minimized == last_minimized_) return;
  last_maximized_ = maximized; last_minimized_ = minimized;
  channel_->InvokeMethod("windowState", std::make_unique<flutter::EncodableValue>(State()));
}

LRESULT WindowFrame::HitTest(LPARAM point) const {
  if (!enabled_) return HTCLIENT;
  POINT cursor{GET_X_LPARAM(point), GET_Y_LPARAM(point)};
  if (!ScreenToClient(window_, &cursor)) return HTCLIENT;
  RECT client{}; GetClientRect(window_, &client);
  if (!IsZoomed(window_)) {
    const UINT dpi = GetDpiForWindow(window_);
    const int border = GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
    const bool left = cursor.x < border;
    const bool right = cursor.x >= client.right - border;
    const bool top = cursor.y < border;
    const bool bottom = cursor.y >= client.bottom - border;
    if (top && left) return HTTOPLEFT;
    if (top && right) return HTTOPRIGHT;
    if (bottom && left) return HTBOTTOMLEFT;
    if (bottom && right) return HTBOTTOMRIGHT;
    if (left) return HTLEFT;
    if (right) return HTRIGHT;
    if (top) return HTTOP;
    if (bottom) return HTBOTTOM;
  }
  if (cursor.y >= 0 && cursor.y < Pixels(window_, kCaptionHeight) &&
      cursor.x >= 0 && cursor.x < client.right - Pixels(window_, kControlsWidth)) return HTCAPTION;
  return HTCLIENT;
}

LRESULT CALLBACK WindowFrame::ChildProc(HWND child, UINT message, WPARAM wparam,
                                        LPARAM lparam, UINT_PTR, DWORD_PTR owner) {
  const auto* frame = reinterpret_cast<WindowFrame*>(owner);
  if (message == WM_NCHITTEST && frame->HitTest(lparam) != HTCLIENT) {
    // Let the same-thread parent own native moving/resizing, including double
    // click, system menu, drag-to-snap and standard keyboard window commands.
    return HTTRANSPARENT;
  }
  return DefSubclassProc(child, message, wparam, lparam);
}

std::optional<LRESULT> WindowFrame::Handle(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_SIZE) NotifyState();
  if (!enabled_) return std::nullopt;
  if (message == WM_NCHITTEST) return HitTest(lparam);
  if (message == WM_NCCALCSIZE && wparam) {
    if (IsZoomed(window_)) {
      MONITORINFO monitor{sizeof(MONITORINFO)};
      if (GetMonitorInfoW(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &monitor)) {
        reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam)->rgrc[0] = monitor.rcWork;
      }
    }
    return 0;
  }
  if (message == WM_GETMINMAXINFO) {
    auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
    limits->ptMinTrackSize.x = Pixels(window_, 360);
    limits->ptMinTrackSize.y = Pixels(window_, 320);
    return 0;
  }
  return std::nullopt;
}
