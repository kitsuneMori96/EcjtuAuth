import 'package:http/http.dart' as http;

import '../models/operator.dart';
import 'app_config.dart';

/// Dr.COM eportal 认证协议客户端。
///
/// 协议流程：
/// 1. GET `http://{host}/` 从页面 JS 中提取本机 IP（v46ip / v4ip）；
/// 2. 携带表单向 `http://{host}:801/eportal/?c=ACSetting&a=Login` POST 登录。
///
/// 登录成败以 POST 后的连通性复验为准（见 NetworkChecker），
/// 本类只负责协议交互，不判断结果。
class EportalClient {
  EportalClient({http.Client? client, AppConfig? config})
      : _client = client ?? http.Client(),
        config = config ?? const AppConfig();

  final http.Client _client;
  final AppConfig config;

  static final RegExp _v46ip = RegExp("v46ip='(.*?)'");
  static final RegExp _v4ip = RegExp("v4ip='(.*?)'");

  static const Map<String, String> requestHeaders = {
    'User-Agent':
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
  };

  Uri get portalUri => Uri.parse('http://${config.portalHost}/');

  Uri _eportalUri(Map<String, String> query) => Uri.http(
        '${config.portalHost}:${AppConfig.portalPort}',
        '/eportal/',
        query,
      );

  /// 拉取 portal 页面原文；不可达时抛出异常。失败后自动重试 1 次。
  Future<String> fetchPortalPage() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _client
            .get(portalUri, headers: requestHeaders)
            .timeout(config.requestTimeout);
        if (res.statusCode != 200) {
          throw http.ClientException('portal responded ${res.statusCode}');
        }
        return res.body;
      } catch (e) {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        rethrow;
      }
    }
    throw http.ClientException('portal fetch failed after retries');
  }

  /// 从 portal 页面提取本机在校园网内的 IP（已 trim）。
  String? extractIp(String html) {
    return (_v46ip.firstMatch(html)?.group(1) ??
            _v4ip.firstMatch(html)?.group(1))
        ?.trim();
  }

  Uri buildLoginUri(String ip) => _eportalUri({
        'c': 'ACSetting',
        'a': 'Login',
        'protocol': 'http:',
        'hostname': config.portalHost,
        'iTermType': '1',
        'wlanuserip': ip,
        'wlanacip': 'null',
        'wlanacname': 'null',
        'mac': '00-00-00-00-00-00',
        'ip': ip,
        'enAdvert': '0',
        'queryACIP': '0',
        'loginMethod': '1',
      });

  /// 构造登录表单。[freeAccess] 为图书馆免费网络（不带运营商后缀）。
  Map<String, String> buildLoginBody({
    required String username,
    required String password,
    Operator operator = Operator.campus,
    bool freeAccess = false,
  }) {
    final account = freeAccess
        ? ',0,$username'
        : ',0,$username${operator.suffix}';
    return {
      'DDDDD': account,
      'upass': password,
      'R1': '0',
      'R2': '0',
      'R3': '0',
      'R6': '0',
      'para': '00',
      '0MKKey': '123456',
      'buttonClicked': '',
      'redirect_url': '',
      'err_flag': '',
      'username': '',
      'password': '',
      'user': '',
      'cmd': '',
      'Login': '',
    };
  }

  /// 发起登录请求。返回 (httpOk, detail)。
  Future<(bool, String)> postLogin({
    required String ip,
    required String username,
    required String password,
    Operator operator = Operator.campus,
    bool freeAccess = false,
  }) async {
    final uri = buildLoginUri(ip);
    final body = buildLoginBody(
      username: username,
      password: password,
      operator: operator,
      freeAccess: freeAccess,
    );
    final res = await _client
        .post(uri, headers: requestHeaders, body: body)
        .timeout(config.requestTimeout);
    final bodySnippet = res.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final detail =
        'HTTP ${res.statusCode} | url=$uri | DDDDD=${body['DDDDD']} | resp=${bodySnippet.length > 200 ? bodySnippet.substring(0, 200) : bodySnippet}';
    return (res.statusCode >= 200 && res.statusCode < 400, detail);
  }

}

class EportalException implements Exception {
  const EportalException(this.message);

  final String message;

  @override
  String toString() => 'EportalException: $message';
}
