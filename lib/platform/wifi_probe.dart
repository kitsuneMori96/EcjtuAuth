import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// 获取当前连接的 WiFi SSID。
/// Android 需要定位权限；Windows 优先插件、失败时回退 netsh 解析。
class WifiProbe {
  const WifiProbe();

  static final NetworkInfo _info = NetworkInfo();

  Future<String?> currentSsid() async {
    if (Platform.isWindows) {
      final viaPlugin = await _safePlugin();
      if (viaPlugin != null) return viaPlugin;
      return _viaNetsh();
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
        'netsh',
        ['wlan', 'show', 'interfaces'],
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
