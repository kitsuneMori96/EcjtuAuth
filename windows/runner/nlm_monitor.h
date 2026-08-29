#ifndef RUNNER_NLM_MONITOR_H_
#define RUNNER_NLM_MONITOR_H_

#include <flutter/binary_messenger.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#define INITGUID
#include <netlistmgr.h>
#undef INITGUID

class NlmMonitor {
 public:
  explicit NlmMonitor(flutter::BinaryMessenger* messenger);
  ~NlmMonitor();

  NlmMonitor(const NlmMonitor&) = delete;
  NlmMonitor& operator=(const NlmMonitor&) = delete;

  void Start();
  void Stop();

  std::string GetCurrentSsid();

 private:
  class NetworkListManagerEvents;

  void OnConnectivityChanged();
  void StartComThread();
  void StopComThread();
  void UnregisterCallback();
  void SendEvent(const std::string& event_type, const std::string& ssid);

  std::wstring GetSsidForConnection(INetworkConnection* connection);

  flutter::BinaryMessenger* messenger_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  std::thread com_thread_;
  std::atomic<bool> running_{false};

  INetworkListManager* nlm_ = nullptr;
  IConnectionPoint* connection_point_ = nullptr;
  DWORD cookie_ = 0;
  NetworkListManagerEvents* callback_ = nullptr;

  std::mutex mutex_;
  std::atomic<bool> initialized_{false};
};

#endif  // RUNNER_NLM_MONITOR_H_
