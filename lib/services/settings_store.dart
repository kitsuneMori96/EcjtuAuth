import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../models/operator.dart';

/// 应用设置（SharedPreferences 持久化）。
class AppSettings {
  const AppSettings({
    this.portalHost = AppConfig.defaultPortalHost,
    this.ssidCampus = AppConfig.defaultSsidCampus,
    this.ssidFree = AppConfig.defaultSsidFree,
    this.autoRetry = true,
    this.baseRetryDelaySec = 10,
    this.maxRetryDelaySec = 300,
    this.launchAtStartup = false,
    this.autoConnectOnResume = true,
  });

  final String portalHost;
  final String ssidCampus;
  final String ssidFree;
  final bool autoRetry;
  final int baseRetryDelaySec;
  final int maxRetryDelaySec;

  /// Windows：开机自启。
  final bool launchAtStartup;

  /// Android：回到前台时自动连接（对齐原项目行为）。
  final bool autoConnectOnResume;

  Duration get baseRetryDelay => Duration(seconds: baseRetryDelaySec);
  Duration get maxRetryDelay => Duration(seconds: maxRetryDelaySec);

  AppSettings copyWith({
    String? portalHost,
    String? ssidCampus,
    String? ssidFree,
    bool? autoRetry,
    int? baseRetryDelaySec,
    int? maxRetryDelaySec,
    bool? launchAtStartup,
    bool? autoConnectOnResume,
  }) {
    return AppSettings(
      portalHost: portalHost ?? this.portalHost,
      ssidCampus: ssidCampus ?? this.ssidCampus,
      ssidFree: ssidFree ?? this.ssidFree,
      autoRetry: autoRetry ?? this.autoRetry,
      baseRetryDelaySec: baseRetryDelaySec ?? this.baseRetryDelaySec,
      maxRetryDelaySec: maxRetryDelaySec ?? this.maxRetryDelaySec,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      autoConnectOnResume: autoConnectOnResume ?? this.autoConnectOnResume,
    );
  }

  Map<String, Object> toMap() => {
        'portalHost': portalHost,
        'ssidCampus': ssidCampus,
        'ssidFree': ssidFree,
        'autoRetry': autoRetry,
        'baseRetryDelaySec': baseRetryDelaySec,
        'maxRetryDelaySec': maxRetryDelaySec,
        'launchAtStartup': launchAtStartup,
        'autoConnectOnResume': autoConnectOnResume,
      };

  factory AppSettings.fromMap(Map<String, Object> map) {
    return AppSettings(
      portalHost: map['portalHost'] as String? ?? AppConfig.defaultPortalHost,
      ssidCampus:
          map['ssidCampus'] as String? ?? AppConfig.defaultSsidCampus,
      ssidFree: map['ssidFree'] as String? ?? AppConfig.defaultSsidFree,
      autoRetry: map['autoRetry'] as bool? ?? true,
      baseRetryDelaySec: map['baseRetryDelaySec'] as int? ?? 10,
      maxRetryDelaySec: map['maxRetryDelaySec'] as int? ?? 300,
      launchAtStartup: map['launchAtStartup'] as bool? ?? false,
      autoConnectOnResume: map['autoConnectOnResume'] as bool? ?? true,
    );
  }
}

class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'settings.';

  Future<AppSettings> load() async {
    final raw = _prefs.getString(_prefix);
    if (raw == null) return const AppSettings();
    try {
      final map = Map<String, Object>.from(Uri.splitQueryString(raw));
      return AppSettings.fromMap(map);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    final encoded = Uri(queryParameters: {
      'portalHost': s.portalHost,
      'ssidCampus': s.ssidCampus,
      'ssidFree': s.ssidFree,
      'autoRetry': s.autoRetry ? '1' : '0',
      'baseRetryDelaySec': '${s.baseRetryDelaySec}',
      'maxRetryDelaySec': '${s.maxRetryDelaySec}',
      'launchAtStartup': s.launchAtStartup ? '1' : '0',
      'autoConnectOnResume': s.autoConnectOnResume ? '1' : '0',
    }).query;
    await _prefs.setString(_prefix, encoded);
  }
}

/// 运营商下拉框用的便捷列表。
const allOperators = Operator.values;
