import 'app_config.dart';
import 'eportal_client.dart';
import '../models/net_state.dart';

/// 网络状态检测器：区分「不在校园网」「校园网待认证」「在线」三态。
///
/// 检测逻辑：对比 portal 页面内容指纹。
/// - 首次 check() 保存离线指纹（登录页）
/// - 后续 check() 对比响应：相同→离线，不同→在线
class NetworkChecker {
  NetworkChecker({
    EportalClient? eportal,
    AppConfig? config,
  })  : _eportal = eportal ?? EportalClient(config: config),
        config = config ?? const AppConfig();

  final EportalClient _eportal;
  final AppConfig config;

  /// 离线时 portal 页面的响应指纹（body 内容）。
  String? _offlineFingerprint;

  /// 缓存的本机 IP（从 portal 页面提取）。
  String? _cachedIp;

  /// 获取缓存的 IP（由 check() 填充）。
  String? get cachedIp => _cachedIp;

  Future<NetState> check() async {
    String portalBody;
    try {
      portalBody = await _eportal.fetchPortalPage();
    } catch (_) {
      return NetState.noCampusWifi;
    }

    // 缓存 IP
    _cachedIp = _eportal.extractIp(portalBody);

    // 首次：保存离线指纹
    _offlineFingerprint ??= portalBody;

    // 对比当前响应与离线指纹
    if (portalBody == _offlineFingerprint) {
      return NetState.campusBlocked;
    }

    return NetState.online;
  }

  /// 重置指纹（登出或切换账号时调用）。
  void resetFingerprint() {
    _offlineFingerprint = null;
    _cachedIp = null;
  }
}
