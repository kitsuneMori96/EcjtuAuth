#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "nlm_monitor.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
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

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
