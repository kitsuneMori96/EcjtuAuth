import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'eportal_client.dart';
import '../models/net_state.dart';

/// 网络状态检测器：区分「不在校园网」「校园网待认证」「在线」三态。
class NetworkChecker {
  NetworkChecker({
    http.Client? client,
    EportalClient? eportal,
    AppConfig? config,
  })  : _client = client ?? http.Client(),
        _eportal = eportal ?? EportalClient(client: client, config: config),
        config = config ?? const AppConfig();

  final http.Client _client;
  final EportalClient _eportal;
  final AppConfig config;

  Future<NetState> check() async {
    try {
      await _eportal.fetchPortalPage();
    } catch (_) {
      return NetState.noCampusWifi;
    }
    return await probeInternet() ? NetState.online : NetState.campusBlocked;
  }

  /// 任一探测地址可达即视为在线。
  ///
  /// 对 generate_204 类 URL 严格要求 204 状态码（captive portal 拦截后
  /// 通常返回 200 + HTML，不能当作真在线）。
  /// 对普通 URL 要求 2xx 且响应体不含 HTML 标签（排除被劫持的页面）。
  Future<bool> probeInternet() async {
    for (final url in config.probeUrls) {
      try {
        final res = await _client
            .get(Uri.parse(url), headers: EportalClient.requestHeaders)
            .timeout(config.requestTimeout);
        final isGenerate204 = Uri.parse(url).path.contains('generate_204');
        if (isGenerate204) {
          if (res.statusCode == 204) return true;
        } else {
          if (res.statusCode >= 200 &&
              res.statusCode < 300 &&
              res.body.isNotEmpty &&
              !res.body.contains('<')) {
            return true;
          }
        }
      } catch (_) {}
    }
    return false;
  }
}
