import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import 'nlm_service.dart';

/// 获取当前连接的 WiFi SSID。
/// Android 需要定位权限；Windows 优先 NLM（事件驱动），失败时回退 netsh。
class WifiProbe {
  WifiProbe({NlmService? nlmService}) : _nlmService = nlmService;

  final NlmService? _nlmService;
  static final NetworkInfo _info = NetworkInfo();

  Future<String?> currentSsid() async {
    if (Platform.isWindows) {
      // 优先用 NLM MethodChannel 获取 SSID。
      final nlm = _nlmService;
      if (nlm != null) {
        final viaNlm = await nlm.getCurrentSsid();
        if (viaNlm != null && viaNlm.isNotEmpty) return viaNlm;
      }
      // 回退到 netsh。
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
