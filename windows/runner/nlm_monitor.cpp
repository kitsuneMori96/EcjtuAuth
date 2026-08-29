#include "nlm_monitor.h"

#include <flutter/encodable_value.h>

#include <iostream>

namespace {

constexpr char kEventChannelName[] = "ecjtu_auth/network_events";
constexpr char kMethodChannelName[] = "ecjtu_auth/network_methods";

}  // namespace

// ---------------------------------------------------------------------------
// StreamHandler: bridges Flutter EventChannel to the NlmMonitor.
// ---------------------------------------------------------------------------

class NlmStreamHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit NlmStreamHandler(NlmMonitor* monitor) : monitor_(monitor) {}

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListen(const flutter::EncodableValue* args,
           std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
               events) override {
    std::lock_guard lock(monitor_->mutex_);
    monitor_->event_sink_ = std::move(events);
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancel(const flutter::EncodableValue* args) override {
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

class NlmMonitor::NetworkListManagerEvents
    : public INetworkListManagerEvents {
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

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** ppv) override {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;

    if (riid == IID_IUnknown ||
        riid == IID_INetworkListManagerEvents) {
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

  HRESULT STDMETHODCALLTYPE ConnectivityChanged(
      NLM_CONNECTIVITY newConnectivity) override {
    monitor_->OnConnectivityChanged();
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE NetworkConnectionPropertyChanged(
      GUID networkId,
      NLM_ENUM_NETWORK_CONNECTION_STATUS_FLAGS statusFlags) override {
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE NetworkPropertyChanged(
      GUID networkId, NLM_ENUM_NETWORK propertyChange) override {
    return S_OK;
  }

 private:
  NlmMonitor* monitor_;
  volatile LONG ref_count_{1};
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
  StartComThread();
}

void NlmMonitor::Stop() {
  running_ = false;
  StopComThread();
}

// ---------------------------------------------------------------------------
// COM thread.
// ---------------------------------------------------------------------------

void NlmMonitor::StartComThread() {
  com_thread_ = std::thread([this]() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) return;

    hr = CoCreateInstance(CLSID_NetworkListManager, nullptr, CLSCTX_SERVER,
                          IID_INetworkListManager,
                          reinterpret_cast<void**>(&nlm_));
    if (FAILED(hr) || !nlm_) {
      CoUninitialize();
      return;
    }

    IConnectionPointContainer* cpc = nullptr;
    hr = nlm_->QueryInterface(IID_IConnectionPointContainer,
                              reinterpret_cast<void**>(&cpc));
    if (FAILED(hr) || !cpc) {
      nlm_->Release();
      nlm_ = nullptr;
      CoUninitialize();
      return;
    }

    IConnectionPoint* cp = nullptr;
    hr = cpc->FindConnectionPoint(IID_INetworkListManagerEvents, &cp);
    cpc->Release();
    if (FAILED(hr) || !cp) {
      nlm_->Release();
      nlm_ = nullptr;
      CoUninitialize();
      return;
    }

    callback_ = new NetworkListManagerEvents(this);

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

    MSG msg;
    while (running_ && GetMessage(&msg, nullptr, 0, 0)) {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
    }

    UnregisterCallback();
    CoUninitialize();
  });
}

void NlmMonitor::StopComThread() {
  if (com_thread_.joinable()) {
    PostThreadMessage(GetThreadId(com_thread_.native_handle()), WM_QUIT, 0, 0);
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
// Connectivity changed callback.
// ---------------------------------------------------------------------------

void NlmMonitor::OnConnectivityChanged() {
  if (!nlm_) return;

  // Check if any connection has internet connectivity.
  IEnumNetworkConnections* enum_conns = nullptr;
  HRESULT hr = nlm_->GetNetworkConnections(&enum_conns);
  if (FAILED(hr) || !enum_conns) return;

  INetworkConnection* conn = nullptr;
  ULONG fetched = 0;
  bool found_connected = false;
  std::string ssid;

  while (enum_conns->Next(1, &conn, &fetched) == S_OK && fetched > 0) {
    NLM_CONNECTIVITY connectivity = NLM_CONNECTIVITY_DISCONNECTED;
    conn->GetConnectivity(&connectivity);

    bool has_connectivity =
        (connectivity & NLM_CONNECTIVITY_IPV4_CONNECTED) ||
        (connectivity & NLM_CONNECTIVITY_IPV6_CONNECTED);

    if (has_connectivity) {
      found_connected = true;
      std::wstring wssid = GetSsidForConnection(conn);
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

  SendEvent(found_connected ? "connected" : "disconnected", ssid);
}

std::wstring NlmMonitor::GetSsidForConnection(INetworkConnection* connection) {
  if (!connection) return L"";

  INetwork* network = nullptr;
  HRESULT hr = connection->GetNetwork(&network);
  if (FAILED(hr) || !network) return L"";

  BSTR name = nullptr;
  hr = network->GetName(&name);
  std::wstring result;
  if (SUCCEEDED(hr) && name) {
    result.assign(name, SysStringLen(name));
    SysFreeString(name);
  }
  network->Release();
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
// Query current SSID.
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
    NLM_CONNECTIVITY connectivity = NLM_CONNECTIVITY_DISCONNECTED;
    conn->GetConnectivity(&connectivity);

    bool has_connectivity =
        (connectivity & NLM_CONNECTIVITY_IPV4_CONNECTED) ||
        (connectivity & NLM_CONNECTIVITY_IPV6_CONNECTED);

    if (has_connectivity) {
      std::wstring wssid = GetSsidForConnection(conn);
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
