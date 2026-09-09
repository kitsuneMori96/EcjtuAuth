import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'eportal_client.dart';
import '../models/net_state.dart';

/// 网络状态检测器：区分「不在校园网」「校园网待认证」「在线」三态。
///
/// 检测逻辑：对比 portal 页面响应长度与用户校准的离线页面长度。
/// - 用户在设置页手动校准离线页面长度
/// - check() 对比当前响应长度：相同→离线，不同→在线
class NetworkChecker {
  NetworkChecker({
    EportalClient? eportal,
    AppConfig? config,
  })  : _eportal = eportal ?? EportalClient(config: config),
        config = config ?? const AppConfig();

  final EportalClient _eportal;
  final AppConfig config;

  static const _repoLengthUrl =
      'https://raw.githubusercontent.com/kitsuneMori96/EcjtuAuth/main/portal_length.txt';

  /// 校准后的离线页面长度（由 settings 传入）。
  int? offlinePageLength;

  /// 从公网仓库拉取基准长度，短超时，失败静默。
  Future<void> _tryFetchBaseline() async {
    try {
      final res = await http.get(Uri.parse(_repoLengthUrl))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final length = int.tryParse(res.body.trim());
      if (length == null || length <= 0) return;
      offlinePageLength = length;
    } catch (_) {}
  }

  Future<NetState> check() async {
    String portalBody;
    try {
      portalBody = await _eportal.fetchPortalPage();
    } catch (_) {
      return NetState.noCampusWifi;
    }

    // 未校准：趁网络可用补一次基准
    if (offlinePageLength == null) {
      await _tryFetchBaseline();
      if (offlinePageLength == null) {
        return NetState.campusBlocked;
      }
    }

    // 对比长度
    return portalBody.length == offlinePageLength
        ? NetState.campusBlocked
        : NetState.online;
  }
}
