#include "nlm_monitor.h"

#include <flutter/encodable_value.h>

#include <iostream>

namespace {

constexpr char kEventChannelName[] = "ecjtu_auth/network_events";
constexpr char kMethodChannelName[] = "ecjtu_auth/network_methods";
constexpr int kPollIntervalMs = 2000;

}  // namespace

// ---------------------------------------------------------------------------
// StreamHandler.
// ---------------------------------------------------------------------------

class NlmMonitor::NlmStreamHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit NlmStreamHandler(NlmMonitor* monitor) : monitor_(monitor) {}

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
          events) override {
    std::lock_guard lock(monitor_->mutex_);
    monitor_->event_sink_ = std::move(events);
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(
      const flutter::EncodableValue* arguments) override {
    std::lock_guard lock(monitor_->mutex_);
    monitor_->event_sink_ = nullptr;
    return nullptr;
  }

 private:
  NlmMonitor* monitor_;
};

// ---------------------------------------------------------------------------
// NlmMonitor implementation.
// ---------------------------------------------------------------------------

NlmMonitor::NlmMonitor(flutter::BinaryMessenger* messenger)
    : messenger_(messenger) {
  event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger_, kEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<NlmStreamHandler>(this);
  event_channel_->SetStreamHandler(std::move(handler));

  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger_, kMethodChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "getCurrentSsid") {
          flutter::EncodableMap map;
          map[flutter::EncodableValue("ssid")] =
              flutter::EncodableValue(GetCurrentSsid());
          result->Success(flutter::EncodableValue(map));
        } else {
          result->NotImplemented();
        }
      });
}

NlmMonitor::~NlmMonitor() {
  Stop();
}

void NlmMonitor::Start() {
  if (running_) return;
  running_ = true;
  poll_thread_ = std::thread(&NlmMonitor::PollLoop, this);
}

void NlmMonitor::Stop() {
  running_ = false;
  if (poll_thread_.joinable()) {
    poll_thread_.join();
  }
}

// ---------------------------------------------------------------------------
// Background polling loop.
// ---------------------------------------------------------------------------

void NlmMonitor::PollLoop() {
  bool initial = CheckInternetConnectivity();
  {
    std::lock_guard lock(mutex_);
    last_connected_ = initial;
  }
  if (initial) {
    SendEvent("connected", GetConnectedSsid());
  }

  while (running_) {
    Sleep(kPollIntervalMs);
    if (!running_) break;

    bool connected = CheckInternetConnectivity();

    bool changed = false;
    {
      std::lock_guard lock(mutex_);
      if (connected != last_connected_) {
        last_connected_ = connected;
        changed = true;
      }
    }

    if (changed) {
      if (connected) {
        SendEvent("connected", GetConnectedSsid());
      } else {
        SendEvent("disconnected", "");
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Check internet connectivity via adapter status.
// ---------------------------------------------------------------------------

bool NlmMonitor::CheckInternetConnectivity() {
  ULONG buf_len = 0;
  GetAdaptersAddresses(AF_UNSPEC, 0, nullptr, nullptr, &buf_len);

  if (buf_len == 0) return false;

  std::vector<BYTE> buf(buf_len);
  auto* adapter = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buf.data());

  ULONG ret = GetAdaptersAddresses(AF_UNSPEC, 0, nullptr, adapter, &buf_len);
  if (ret != NO_ERROR) return false;

  for (auto* a = adapter; a != nullptr; a = a->Next) {
    if (a->OperStatus != IfOperStatusUp) continue;
    if (a->IfType == IF_TYPE_IEEE80211 ||  // WiFi
        a->IfType == IF_TYPE_ETHERNET_CSMACD) {  // Ethernet
      if (a->FirstUnicastAddress != nullptr) {
        return true;
      }
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Get connected SSID via netsh.
// ---------------------------------------------------------------------------

std::string NlmMonitor::GetConnectedSsid() {
  // Release mutex before spawning process to avoid blocking.
  // The result is captured locally.
  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
  si.wShowWindow = SW_HIDE;

  HANDLE hRead = nullptr, hWrite = nullptr;
  SECURITY_ATTRIBUTES sa = {};
  sa.nLength = sizeof(sa);
  sa.bInheritHandle = TRUE;
  if (!CreatePipe(&hRead, &hWrite, &sa, 0)) return "";

  si.hStdOutput = hWrite;
  si.hStdError = hWrite;

  PROCESS_INFORMATION pi = {};
  BOOL ok = CreateProcessW(
      nullptr,
      L"cmd.exe /c netsh wlan show interfaces",
      nullptr, nullptr, TRUE,
      CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);

  CloseHandle(hWrite);
  if (!ok) {
    CloseHandle(hRead);
    return "";
  }

  WaitForSingleObject(pi.hProcess, 3000);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);

  char buf[4096] = {};
  DWORD read_bytes = 0;
  ReadFile(hRead, buf, sizeof(buf) - 1, &read_bytes, nullptr);
  CloseHandle(hRead);

  std::string output(buf, read_bytes);
  std::string ssid;
  for (size_t pos = 0; pos < output.size();) {
    size_t eol = output.find('\n', pos);
    if (eol == std::string::npos) eol = output.size();
    std::string line = output.substr(pos, eol - pos);
    pos = eol + 1;

    if (line.find("SSID") != std::string::npos &&
        line.find("BSSID") == std::string::npos) {
      size_t colon = line.find(':');
      if (colon != std::string::npos && colon + 1 < line.size()) {
        ssid = line.substr(colon + 1);
        // Trim whitespace.
        while (!ssid.empty() && ssid.back() == '\r') ssid.pop_back();
        size_t start = ssid.find_first_not_of(' ');
        if (start != std::string::npos) ssid = ssid.substr(start);
        break;
      }
    }
  }
  return ssid;
}

// ---------------------------------------------------------------------------
// Send event to Dart.
// ---------------------------------------------------------------------------

void NlmMonitor::SendEvent(const std::string& event_type,
                            const std::string& ssid) {
  std::lock_guard lock(mutex_);
  if (!event_sink_) return;

  flutter::EncodableMap map;
  map[flutter::EncodableValue("event")] =
      flutter::EncodableValue(event_type);
  map[flutter::EncodableValue("ssid")] =
      flutter::EncodableValue(ssid);

  event_sink_->Success(flutter::EncodableValue(map));
}

// ---------------------------------------------------------------------------
// Query current SSID (called from Dart).
// ---------------------------------------------------------------------------

std::string NlmMonitor::GetCurrentSsid() {
  return GetConnectedSsid();
}
