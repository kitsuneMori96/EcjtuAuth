import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import 'nlm_service.dart';

/// 获取当前连接的 WiFi SSID。
///
/// **单一来源**：优先走平台通道（Windows `netsh` / Android `ConnectivityManager`），
/// `network_info_plus` 只在平台通道不可用时兜底。
///
/// 之前 Android 走插件、事件走平台通道，两者底层都是
/// `WifiManager.connectionInfo`，但实测在「撤销定位权限」时给出不同结果
/// （卡片显示 ECJTU-Stu、事件 ssid 为空），导致 UI 文案与核心层判定互相矛盾。
class WifiProbe {
  /// [androidOverride] 仅用于测试注入，生产代码不要传。
  WifiProbe({NlmService? nlmService, bool? androidOverride})
      : _nlmService = nlmService,
        _androidOverride = androidOverride;

  final NlmService? _nlmService;
  final bool? _androidOverride;
  static final NetworkInfo _info = NetworkInfo();

  bool get _isAndroid => _androidOverride ?? Platform.isAndroid;

  Future<String?> currentSsid() async {
    if (Platform.isWindows) {
      // 优先用 NLM MethodChannel 获取 SSID，失败回退 netsh。
      final viaNlm = await _nlmService?.getCurrentSsid();
      if (viaNlm != null && viaNlm.isNotEmpty) return viaNlm;
      return _viaNetsh();
    }

    if (_isAndroid) {
      final network = await _nlmService?.currentNetwork();
      // 通道可用就以它为准：wifi 但读不到名字时返回 null，
      // 不再回退插件去「碰运气」，否则又会出现双源不一致。
      if (network != null) {
        return network.type.isWifi && network.hasSsid ? network.ssid : null;
      }
      // 通道不可用（老原生实现 / 初始化失败）才兜底。
      return _safePlugin();
    }

    return _safePlugin();
  }

  Future<String?> _safePlugin() async {
    try {
      return await _info.getWifiName();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _viaNetsh() async {
    try {
      final result = await Process.run(
        'cmd.exe',
        ['/c', 'chcp 65001 >nul & netsh wlan show interfaces'],
        stdoutEncoding: systemEncoding,
      );
      for (final line in result.stdout.toString().split('\n')) {
        if (line.contains('SSID') && !line.contains('BSSID')) {
          final idx = line.indexOf(':');
          if (idx >= 0 && idx + 1 < line.length) {
            return line.substring(idx + 1).trim();
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
