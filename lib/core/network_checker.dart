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
  Future<bool> probeInternet() async {
    for (final url in config.probeUrls) {
      try {
        final res = await _client
            .get(Uri.parse(url), headers: EportalClient.requestHeaders)
            .timeout(config.requestTimeout);
        if (res.statusCode >= 200 && res.statusCode < 300) return true;
      } catch (_) {}
    }
    return false;
  }
}
