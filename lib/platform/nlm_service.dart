import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// 当前默认网络的链路类型。
///
/// 取值与原生侧（`windows/runner/nlm_monitor.cpp`、Android `MainActivity`）一致；
/// [unknown] 用于老版本原生实现或取不到类型时，调用方应回退到旧行为而不是当成「无网络」。
enum NetworkType {
  wifi,
  cellular,
  ethernet,
  none,
  unknown;

  static NetworkType parse(Object? raw) => switch (raw) {
        'wifi' => NetworkType.wifi,
        'cellular' => NetworkType.cellular,
        'ethernet' => NetworkType.ethernet,
        'none' => NetworkType.none,
        _ => NetworkType.unknown,
      };

  bool get isWifi => this == NetworkType.wifi;

  /// 明确没有默认网络（飞行模式、无连接）。[unknown] 不算「没有」。
  bool get isNoNetwork => this == NetworkType.none;
}

class NlmNetworkEvent {
  final String event;
  final String ssid;
  final NetworkType type;

  const NlmNetworkEvent({
    required this.event,
    required this.ssid,
    this.type = NetworkType.unknown,
  });

  bool get isConnected => event == 'connected';
  bool get isDisconnected => event == 'disconnected';
  bool get isWake => event == 'wake';
  bool get isSuspend => event == 'suspend';

  @override
  String toString() => 'NlmNetworkEvent($event, ssid=$ssid, type=$type)';
}

/// 某个时刻的网络快照（查询，非事件）。
class CurrentNetwork {
  const CurrentNetwork({
    required this.type,
    required this.ssid,
    required this.ssidVisible,
  });

  final NetworkType type;
  final String ssid;

  /// WiFi 已连接但读不到名字（未授予定位权限 / ROM 限制）。
  /// 与「没有 WiFi」严格区分：此时 [type] 仍是 [NetworkType.wifi]。
  final bool ssidVisible;

  bool get hasSsid => ssid.isNotEmpty;

  @override
  String toString() =>
      'CurrentNetwork($type, ssid=$ssid, ssidVisible=$ssidVisible)';
}

/// 网络状态变化的统一入口。
///
/// 两端共用同一套平台通道，Dart 侧无需区分平台：
/// - Windows：`windows/runner/nlm_monitor.cpp` 的 `netsh` 轮询（自适应 8s/2s）；
/// - Android：`MainActivity` 的 `ConnectivityManager.registerDefaultNetworkCallback`
///   （原生 API，无第三方依赖）。
///
/// 事件载荷均为
/// `{"event": "connected"|"disconnected", "ssid": "...", "type": "wifi|cellular|ethernet|none"}`，
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
          type: NetworkType.parse(data['type']),
        );
        _controller.add(event);
      },
      onError: (Object error) {
        // 原生侧不可用（通道未注册、权限缺失）时静默忽略：
        // 网络变化监听只是优化项，不能让异常影响认证主流程。
      },
    );
  }

  /// 查询当前网络快照。
  ///
  /// 返回 `null` 表示**通道不可用**（老原生实现、初始化失败），调用方应回退到其它探测方式；
  /// 通道可用但没有网络时返回 `type = none` 的对象——这两种情况不能混为一谈。
  Future<CurrentNetwork?> currentNetwork() async {
    if (!isSupported) return null;
    try {
      final result = await _methodChannel.invokeMethod<Map>('getCurrentNetwork');
      if (result == null) return null;
      final ssid = result['ssid'] as String? ?? '';
      return CurrentNetwork(
        type: NetworkType.parse(result['type']),
        ssid: ssid,
        ssidVisible: result['ssidVisible'] as bool? ?? ssid.isNotEmpty,
      );
    } on MissingPluginException {
      // 老版本原生实现没有 getCurrentNetwork，回退由调用方决定。
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<String?> getCurrentSsid() async {
    final network = await currentNetwork();
    if (network != null) {
      return network.hasSsid ? network.ssid : null;
    }
    // 兼容路径：原生实现只提供 getCurrentSsid。
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
