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

#include <windows.h>
#include <iphlpapi.h>
#include <netioapi.h>

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
  class NlmStreamHandler;

  void PollLoop();
  bool CheckInternetConnectivity();
  std::string GetConnectedSsid();
  void SendEvent(const std::string& event_type, const std::string& ssid);

  flutter::BinaryMessenger* messenger_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  std::thread poll_thread_;
  std::atomic<bool> running_{false};
  bool last_connected_ = false;

  mutable std::mutex mutex_;

  friend class NlmStreamHandler;
};

#endif  // RUNNER_NLM_MONITOR_H_
