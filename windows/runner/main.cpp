#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "nlm_monitor.h"
#include "utils.h"

namespace {

// 单实例锁：两个进程同时跑会各自持有一份 NLM 监听与托盘图标，
// 认证状态互相覆盖，且用户无法判断哪个窗口在生效。
// Local\ 前缀表示「当前登录会话内唯一」——RDP/多用户会话各开一份是合理的。
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\EcjtuAuth_SingleInstance";

// 与 win32_window.cpp 中的 kWindowClassName 保持一致。
constexpr wchar_t kMainWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kMainWindowTitle[] = L"EcjtuAuth";

// 第二个实例启动时把已有窗口唤到前台。
// 首个实例可能还没创建窗口（Dart 侧初始化需要几百毫秒），
// 因此短暂重试，避免用户双击后「什么也没发生」。
void ActivateExistingWindow() {
  for (int attempt = 0; attempt < 40; ++attempt) {
    HWND existing = ::FindWindowW(kMainWindowClass, kMainWindowTitle);
    if (existing == nullptr) {
      // 标题可能被改过（例如 window_manager 设置标题），退化为按标题查找。
      existing = ::FindWindowW(nullptr, kMainWindowTitle);
    }
    if (existing != nullptr) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      } else {
        ::ShowWindow(existing, SW_SHOW);
      }
      ::SetForegroundWindow(existing);
      return;
    }
    ::Sleep(100);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // 必须在创建任何窗口/托盘之前抢锁，否则两个进程会短暂并存。
  HANDLE single_instance =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  const bool already_running =
      single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS;
  if (already_running) {
    ActivateExistingWindow();
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // 与 Dart 侧 WindowOptions(430x760, center: true) 保持一致，避免启动时尺寸/位置闪跳。
  Win32Window::Point origin(
      (::GetSystemMetrics(SM_CXSCREEN) - 430) / 2,
      (::GetSystemMetrics(SM_CYSCREEN) - 760) / 2);
  Win32Window::Size size(430, 760);
  if (!window.Create(L"EcjtuAuth", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  std::unique_ptr<NlmMonitor> nlm_monitor;
  auto* messenger = window.GetMessenger();
  if (messenger) {
    nlm_monitor = std::make_unique<NlmMonitor>(messenger);
    window.SetNlmMonitor(nlm_monitor.get());
    nlm_monitor->Start();
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (nlm_monitor) {
    nlm_monitor->Stop();
  }

  if (single_instance != nullptr) {
    ::ReleaseMutex(single_instance);
    ::CloseHandle(single_instance);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
