import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class NlmNetworkEvent {
  final String event;
  final String ssid;

  const NlmNetworkEvent({required this.event, required this.ssid});

  bool get isConnected => event == 'connected';
  bool get isDisconnected => event == 'disconnected';
  bool get isWake => event == 'wake';
  bool get isSuspend => event == 'suspend';

  @override
  String toString() => 'NlmNetworkEvent($event, ssid=$ssid)';
}

/// 网络状态变化的统一入口。
///
/// 两端共用同一套平台通道，Dart 侧无需区分平台：
/// - Windows：`windows/runner/nlm_monitor.cpp` 的 `netsh` 轮询（自适应 8s/2s）；
/// - Android：`MainActivity` 的 `ConnectivityManager.registerDefaultNetworkCallback`
///   （原生 API，无第三方依赖）。
///
/// 事件载荷均为 `{"event": "connected"|"disconnected", "ssid": "..."}`，
/// SSID 拿不到时为空串。其余平台（Linux/macOS/Web）为安全空实现。
class NlmService {
  /// [supportedPlatform] 仅用于测试注入，生产代码不要传。
  NlmService({bool? supportedPlatform}) : _supportedOverride = supportedPlatform;

  static const _eventChannel = EventChannel('ecjtu_auth/network_events');
  static const _methodChannel = MethodChannel('ecjtu_auth/network_methods');

  final bool? _supportedOverride;

  StreamSubscription<Map<dynamic, dynamic>>? _subscription;
  final _controller = StreamController<NlmNetworkEvent>.broadcast();

  /// 是否有原生实现（Windows / Android）。
  bool get isSupported =>
      _supportedOverride ?? (Platform.isWindows || Platform.isAndroid);

  Stream<NlmNetworkEvent> get onNetworkChanged => _controller.stream;

  void startListening() {
    if (!isSupported) return;
    // 重复调用不应叠加原生侧的回调注册（Android 上 registerDefaultNetworkCallback
    // 每次调用都会新增一个回调，重复订阅会成倍放大事件）。
    if (_subscription != null) return;

    _subscription = _eventChannel.receiveBroadcastStream().map((event) {
      return Map<dynamic, dynamic>.from(event as Map);
    }).listen(
      (data) {
        final event = NlmNetworkEvent(
          event: data['event'] as String? ?? 'unknown',
          ssid: data['ssid'] as String? ?? '',
        );
        _controller.add(event);
      },
      onError: (Object error) {
        // 原生侧不可用（通道未注册、权限缺失）时静默忽略：
        // 网络变化监听只是优化项，不能让异常影响认证主流程。
      },
    );
  }

  Future<String?> getCurrentSsid() async {
    if (!isSupported) return null;
    try {
      final result = await _methodChannel.invokeMethod<Map>('getCurrentSsid');
      final ssid = result?['ssid'] as String?;
      return (ssid == null || ssid.isEmpty) ? null : ssid;
    } catch (_) {
      return null;
    }
  }

  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
