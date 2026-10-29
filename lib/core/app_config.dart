/// eportal 协议客户端的运行时配置。
///
/// 实例由 [AppSettings] 在设置加载/保存时生成，因此修改认证服务器地址后
/// 下一次连接立即生效。
class AppConfig {
  const AppConfig({
    this.portalHost = defaultPortalHost,
    this.requestTimeout = defaultRequestTimeout,
  });

  static const String defaultPortalHost = '172.16.2.100';
  static const int portalPort = 801;
  static const String defaultSsidCampus = 'ECJTU-Stu';
  static const String defaultSsidFree = 'EcjtuLib_Free';
  static const Duration defaultRequestTimeout = Duration(seconds: 3);

  final String portalHost;
  final Duration requestTimeout;
}
