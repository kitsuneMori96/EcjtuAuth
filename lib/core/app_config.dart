/// 全局可配置项：默认值来自 ECJTU 校园网现网环境，
/// 全部可在应用内修改并持久化，不硬编码进业务逻辑。
class AppConfig {
  const AppConfig({
    this.portalHost = defaultPortalHost,
    this.ssidCampus = defaultSsidCampus,
    this.ssidFree = defaultSsidFree,
    this.requestTimeout = defaultRequestTimeout,
  });

  static const String defaultPortalHost = '172.16.2.100';
  static const int portalPort = 801;
  static const String defaultSsidCampus = 'ECJTU-Stu';
  static const String defaultSsidFree = 'EcjtuLib_Free';
  static const Duration defaultRequestTimeout = Duration(seconds: 3);

  final String portalHost;
  final String ssidCampus;
  final String ssidFree;
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
    );
  }
}
