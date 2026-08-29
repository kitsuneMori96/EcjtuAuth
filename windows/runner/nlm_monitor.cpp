#include "nlm_monitor.h"

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>

#include <atomic>
#include <functional>
#include <iostream>
#include <sstream>

namespace {

constexpr wchar_t kEventChannelName[] = L"ecjtu_auth/network_events";
constexpr wchar_t kMethodChannelName[] = L"ecjtu_auth/network_methods";

}  // namespace

// ---------------------------------------------------------------------------
// EventSinkHandler: bridges a Flutter EventSink to the NlmMonitor.
// ---------------------------------------------------------------------------

class NlmMonitor::EventSinkHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit EventSinkHandler(NlmMonitor* monitor) : monitor_(monitor) {}

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListen(const flutter::EncodableValue* arguments,
           std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) override {
    std::lock_guard lock(monitor_->mutex_);
    monitor_->event_sink_ = std::move(sink);
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancel(const flutter::EncodableValue* arguments) override {
    std::lock_guard lock(monitor_->mutex_);
    monitor_->event_sink_ = nullptr;
    return nullptr;
  }

 private:
  NlmMonitor* monitor_;
};

// ---------------------------------------------------------------------------
// NetworkListManagerEvents: COM callback implementation.
// ---------------------------------------------------------------------------

class NlmMonitor::NetworkListManagerEvents : public INetworkListManagerEvents {
 public:
  explicit NetworkListManagerEvents(NlmMonitor* monitor) : monitor_(monitor) {}

  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&ref_count_);
  }

  ULONG STDMETHODCALLTYPE Release() override {
    LONG count = InterlockedDecrement(&ref_count_);
    if (count == 0) {
      delete this;
    }
    return count;
  }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;

    if (riid == IID_IUnknown || riid == IID_INetworkListManagerEvents) {
      *ppv = static_cast<INetworkListManagerEvents*>(this);
      AddRef();
      return S_OK;
    }
    return E_NOINTERFACE;
  }

  HRESULT STDMETHODCALLTYPE NetworkAdded(GUID networkId) override {
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE NetworkRemoved(GUID networkId) override {
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE ConnectivityChanged(NLM_CONNECTIVITY newConnectivity) override {
    monitor_->OnConnectivityChanged(newConnectivity);
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE NetworkConnectionPropertyChanged(
      GUID networkId, NLM_ENUM_NETWORK_CONNECTION_STATUS_FLAGS statusFlags) override {
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE NetworkPropertyChanged(
      GUID networkId, NLM_ENUM_NETWORK propertyChange) override {
    return S_OK;
  }

 private:
  NlmMonitor* monitor_;
  std::atomic<ULONG> ref_count_{1};
};

// ---------------------------------------------------------------------------
// NlmMonitor implementation.
// ---------------------------------------------------------------------------

NlmMonitor::NlmMonitor(FlutterDesktopMessenger* messenger)
    : messenger_(messenger) {
  // Set up the EventChannel.
  auto event_ch =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger_, kEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  event_sink_handler_ = std::make_unique<EventSinkHandler>(this);
  event_ch->SetStreamHandler(std::move(event_sink_handler_));

  event_channel_ = std::move(event_ch);

  // Set up the MethodChannel for GetCurrentSsid.
  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger_, kMethodChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "getCurrentSsid") {
          std::string ssid = GetCurrentSsid();
          flutter::EncodableMap map;
          map[flutter::EncodableValue("ssid")] =
              flutter::EncodableValue(ssid);
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
  StartComThread();
}

void NlmMonitor::Stop() {
  running_ = false;
  StopComThread();
}

// ---------------------------------------------------------------------------
// COM thread: runs an STA message pump so that COM callbacks are delivered.
// ---------------------------------------------------------------------------

void NlmMonitor::StartComThread() {
  com_thread_ = std::thread([this]() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) {
      return;
    }

    // Create the Network List Manager.
    hr = CoCreateInstance(CLSID_NetworkListManager, nullptr, CLSCTX_SERVER,
                          IID_INetworkListManager,
                          reinterpret_cast<void**>(&nlm_));
    if (FAILED(hr) || !nlm_) {
      CoUninitialize();
      return;
    }

    // Get IConnectionPointContainer.
    IConnectionPointContainer* cpc = nullptr;
    hr = nlm_->QueryInterface(IID_IConnectionPointContainer,
                              reinterpret_cast<void**>(&cpc));
    if (FAILED(hr) || !cpc) {
      nlm_->Release();
      nlm_ = nullptr;
      CoUninitialize();
      return;
    }

    // Find the connection point for INetworkListManagerEvents.
    IConnectionPoint* cp = nullptr;
    hr = cpc->FindConnectionPoint(IID_INetworkListManagerEvents, &cp);
    cpc->Release();
    if (FAILED(hr) || !cp) {
      nlm_->Release();
      nlm_ = nullptr;
      CoUninitialize();
      return;
    }

    // Create the callback sink.
    callback_ = new NetworkListManagerEvents(this);

    // Advise (register the callback).
    hr = cp->Advise(callback_, &cookie_);
    if (FAILED(hr)) {
      callback_->Release();
      callback_ = nullptr;
      cp->Release();
      nlm_->Release();
      nlm_ = nullptr;
      CoUninitialize();
      return;
    }

    connection_point_ = cp;

    {
      std::lock_guard lock(mutex_);
      initialized_ = true;
    }

    // Run the message pump until Stop() is called.
    MSG msg;
    while (running_ && GetMessage(&msg, nullptr, 0, 0)) {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
    }

    // Cleanup.
    UnregisterCallback();
    CoUninitialize();
  });
}

void NlmMonitor::StopComThread() {
  if (com_thread_.joinable()) {
    // Post WM_QUIT to break the message loop.
    // The thread will clean up COM resources.
    PostThreadMessage(0, WM_QUIT, 0, 0);
    com_thread_.join();
  }

  std::lock_guard lock(mutex_);
  initialized_ = false;
}

void NlmMonitor::UnregisterCallback() {
  if (connection_point_ && cookie_ != 0) {
    connection_point_->Unadvise(cookie_);
    cookie_ = 0;
  }
  if (connection_point_) {
    connection_point_->Release();
    connection_point_ = nullptr;
  }
  if (callback_) {
    callback_->Release();
    callback_ = nullptr;
  }
  if (nlm_) {
    nlm_->Release();
    nlm_ = nullptr;
  }
}

// ---------------------------------------------------------------------------
// Connectivity changed callback (called on COM thread).
// ---------------------------------------------------------------------------

void NlmMonitor::OnConnectivityChanged(NLM_CONNECTIVITY newConnectivity) {
  bool has_connectivity =
      (newConnectivity & NLM_CONNECTIVITY_IPV4_CONNECTED) ||
      (newConnectivity & NLM_CONNECTIVITY_IPV6_CONNECTED);

  if (!has_connectivity) {
    SendEvent("disconnected", "");
    return;
  }

  // Try to get the SSID of the connected network.
  std::string ssid;
  if (nlm_) {
    IEnumNetworkConnections* enum_conns = nullptr;
    HRESULT hr = nlm_->GetNetworkConnections(&enum_conns);
    if (SUCCEEDED(hr) && enum_conns) {
      INetworkConnection* conn = nullptr;
      ULONG fetched = 0;
      while (enum_conns->Next(1, &conn, &fetched) == S_OK && fetched > 0) {
        BOOL is_connected = FALSE;
        conn->IsConnected(&is_connected);
        if (is_connected) {
          std::wstring wssid = GetSsidFromConnection(conn);
          if (!wssid.empty()) {
            // Convert wide string to UTF-8.
            int len = WideCharToMultiByte(CP_UTF8, 0, wssid.c_str(),
                                          static_cast<int>(wssid.size()),
                                          nullptr, 0, nullptr, nullptr);
            if (len > 0) {
              ssid.resize(len);
              WideCharToMultiByte(CP_UTF8, 0, wssid.c_str(),
                                  static_cast<int>(wssid.size()), ssid.data(),
                                  len, nullptr, nullptr);
            }
          }
          conn->Release();
          break;
        }
        conn->Release();
      }
      enum_conns->Release();
    }
  }

  SendEvent("connected", ssid);
}

std::wstring NlmMonitor::GetSsidFromConnection(INetworkConnection* connection) {
  if (!connection) return L"";

  INetwork* network = nullptr;
  HRESULT hr = connection->GetNetwork(&network);
  if (FAILED(hr) || !network) return L"";

  std::wstring ssid = GetSsidFromNetwork(network);
  network->Release();
  return ssid;
}

std::wstring NlmMonitor::GetSsidFromNetwork(INetwork* network) {
  if (!network) return L"";

  BSTR name = nullptr;
  HRESULT hr = network->GetName(&name);
  if (FAILED(hr) || !name) return L"";

  std::wstring result(name, SysStringLen(name));
  SysFreeString(name);
  return result;
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
// Query current SSID (called from Dart via MethodChannel).
// ---------------------------------------------------------------------------

std::string NlmMonitor::GetCurrentSsid() {
  std::lock_guard lock(mutex_);
  if (!initialized_ || !nlm_) return "";

  IEnumNetworkConnections* enum_conns = nullptr;
  HRESULT hr = nlm_->GetNetworkConnections(&enum_conns);
  if (FAILED(hr) || !enum_conns) return "";

  std::string ssid;
  INetworkConnection* conn = nullptr;
  ULONG fetched = 0;
  while (enum_conns->Next(1, &conn, &fetched) == S_OK && fetched > 0) {
    BOOL is_connected = FALSE;
    conn->IsConnected(&is_connected);
    if (is_connected) {
      std::wstring wssid = GetSsidFromConnection(conn);
      if (!wssid.empty()) {
        int len = WideCharToMultiByte(CP_UTF8, 0, wssid.c_str(),
                                      static_cast<int>(wssid.size()),
                                      nullptr, 0, nullptr, nullptr);
        if (len > 0) {
          ssid.resize(len);
          WideCharToMultiByte(CP_UTF8, 0, wssid.c_str(),
                              static_cast<int>(wssid.size()), ssid.data(),
                              len, nullptr, nullptr);
        }
      }
      conn->Release();
      break;
    }
    conn->Release();
  }
  enum_conns->Release();
  return ssid;
}
