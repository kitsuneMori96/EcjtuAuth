import 'dart:convert';

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

  Map<String, Object?> toMap() => {
    'portalHost': portalHost,
    'ssidCampus': ssidCampus,
    'ssidFree': ssidFree,
    'autoRetry': autoRetry,
    'baseRetryDelaySec': baseRetryDelaySec,
    'maxRetryDelaySec': maxRetryDelaySec,
    'launchAtStartup': launchAtStartup,
    'autoConnectOnResume': autoConnectOnResume,
    'offlinePageLength': offlinePageLength,
  };

  factory AppSettings.fromMap(Map<String, Object?> map) {
    return AppSettings(
      portalHost: _string(map['portalHost'], AppConfig.defaultPortalHost),
      ssidCampus: _string(map['ssidCampus'], AppConfig.defaultSsidCampus),
      ssidFree: _string(map['ssidFree'], AppConfig.defaultSsidFree),
      autoRetry: _bool(map['autoRetry'], fallback: true),
      baseRetryDelaySec: _int(map['baseRetryDelaySec'], 10),
      maxRetryDelaySec: _int(map['maxRetryDelaySec'], 300),
      launchAtStartup: _bool(map['launchAtStartup'], fallback: false),
      autoConnectOnResume: _bool(map['autoConnectOnResume'], fallback: true),
      offlinePageLength: _intOrNull(map['offlinePageLength']),
    );
  }

  static String _string(Object? value, String fallback) {
    if (value is String && value.isNotEmpty) return value;
    return fallback;
  }

  static bool _bool(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is String) return value != '0';
    return fallback;
  }

  static int _int(Object? value, int fallback) =>
      value is int ? value : int.tryParse('$value') ?? fallback;

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'settings.v2';
  static const _legacyKey = 'settings.';

  Future<AppSettings> load() async {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return AppSettings.fromMap(decoded.map((k, v) => MapEntry('$k', v)));
        }
      } catch (_) {
        // 损坏的 JSON 回退到默认值/旧格式
      }
    }

    // 兼容 1.x 的 query-string 格式（全字符串键值）。
    final legacy = _prefs.getString(_legacyKey);
    if (legacy != null) {
      try {
        return AppSettings.fromMap(
          Map<String, Object?>.from(Uri.splitQueryString(legacy)),
        );
      } catch (_) {
        // 旧格式损坏，使用默认值
      }
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings s) async {
    await _prefs.setString(_key, jsonEncode(s.toMap()));
  }
}

/// 运营商下拉框用的便捷列表。
const allOperators = Operator.values;
