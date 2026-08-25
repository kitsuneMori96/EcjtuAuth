/// 全局可配置项：默认值来自 ECJTU 校园网现网环境，
/// 全部可在应用内修改并持久化，不硬编码进业务逻辑。
class AppConfig {
  const AppConfig({
    this.portalHost = defaultPortalHost,
    this.ssidCampus = defaultSsidCampus,
    this.ssidFree = defaultSsidFree,
    this.probeUrls = defaultProbeUrls,
    this.requestTimeout = defaultRequestTimeout,
  });

  static const String defaultPortalHost = '172.16.2.100';
  static const int portalPort = 801;
  static const String defaultSsidCampus = 'ECJTU-Stu';
  static const String defaultSsidFree = 'EcjtuLib_Free';
  static const List<String> defaultProbeUrls = [
    'https://www.baidu.com',
    'http://connect.rom.miui.com/generate_204',
  ];
  static const Duration defaultRequestTimeout = Duration(seconds: 4);

  /// 认证服务器地址
  final String portalHost;

  /// 校园教学区 SSID
  final String ssidCampus;

  /// 图书馆免费 SSID
  final String ssidFree;

  /// 在线探测地址，任意一个可达即认为已联网
  final List<String> probeUrls;

  /// 单次 HTTP 请求超时
  final Duration requestTimeout;

  AppConfig copyWith({
    String? portalHost,
    String? ssidCampus,
    String? ssidFree,
  }) {
    return AppConfig(
      portalHost: portalHost ?? this.portalHost,
      ssidCampus: ssidCampus ?? this.ssidCampus,
      ssidFree: ssidFree ?? this.ssidFree,
      probeUrls: probeUrls,
      requestTimeout: requestTimeout,
    );
  }
}
