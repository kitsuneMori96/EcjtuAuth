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
    this.offlinePageLength,
  });

  final String portalHost;
  final String ssidCampus;
  final String ssidFree;
  final bool autoRetry;
  final int baseRetryDelaySec;
  final int maxRetryDelaySec;
  final bool launchAtStartup;
  final bool autoConnectOnResume;

  /// 离线登录页的响应长度（用户手动校准）。
  /// null 表示未校准。
  final int? offlinePageLength;

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
    int? offlinePageLength,
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
      offlinePageLength: offlinePageLength ?? this.offlinePageLength,
    );
  }

  Map<String, Object> toMap() => {
        'portalHost': portalHost,
        'ssidCampus': ssidCampus,
        'ssidFree': ssidFree,
        'autoRetry': autoRetry ? '1' : '0',
        'baseRetryDelaySec': '$baseRetryDelaySec',
        'maxRetryDelaySec': '$maxRetryDelaySec',
        'launchAtStartup': launchAtStartup ? '1' : '0',
        'autoConnectOnResume': autoConnectOnResume ? '1' : '0',
        if (offlinePageLength != null) 'offlinePageLength': '$offlinePageLength',
      };

  factory AppSettings.fromMap(Map<String, Object> map) {
    return AppSettings(
      portalHost: map['portalHost'] as String? ?? AppConfig.defaultPortalHost,
      ssidCampus:
          map['ssidCampus'] as String? ?? AppConfig.defaultSsidCampus,
      ssidFree: map['ssidFree'] as String? ?? AppConfig.defaultSsidFree,
      autoRetry: (map['autoRetry'] as String?) != '0',
      baseRetryDelaySec: int.tryParse(map['baseRetryDelaySec'] as String? ?? '') ?? 10,
      maxRetryDelaySec: int.tryParse(map['maxRetryDelaySec'] as String? ?? '') ?? 300,
      launchAtStartup: (map['launchAtStartup'] as String?) == '1',
      autoConnectOnResume: (map['autoConnectOnResume'] as String?) != '0',
      offlinePageLength: int.tryParse(map['offlinePageLength'] as String? ?? ''),
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
    final encoded = Uri(queryParameters: s.toMap().map(
      (k, v) => MapEntry(k, '$v'),
    )).query;
    await _prefs.setString(_prefix, encoded);
  }
}

/// 运营商下拉框用的便捷列表。
const allOperators = Operator.values;
