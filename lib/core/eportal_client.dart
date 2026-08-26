import 'package:http/http.dart' as http;

import '../models/operator.dart';
import 'app_config.dart';

/// Dr.COM eportal 认证协议客户端。
///
/// 协议流程：
/// 1. GET `http://{host}/` 从页面 JS 中提取本机 IP（v46ip / v4ip）；
/// 2. 携带表单向 `http://{host}:801/eportal/?c=ACSetting&a=Login` POST 登录；
/// 3. 注销需先从 portal 页面提取 olmac 再 POST a=Logout。
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
  static final RegExp _olmac = RegExp("olmac\\s*=\\s*['\"]([^'\"]*)['\"]");

  static const Map<String, String> requestHeaders = {
    'User-Agent':
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
  };

  Uri get portalUri => Uri.parse('http://${config.portalHost}/');

  Uri _eportalUri(Map<String, String> query) => Uri.http(
        config.portalHost,
        ':${AppConfig.portalPort}/eportal/',
        query,
      );

  /// 拉取 portal 页面原文；不可达时抛出异常。
  Future<String> fetchPortalPage() async {
    final res = await _client
        .get(portalUri, headers: requestHeaders)
        .timeout(config.requestTimeout);
    if (res.statusCode != 200) {
      throw http.ClientException('portal responded ${res.statusCode}');
    }
    return res.body;
  }

  /// 从 portal 页面提取本机在校园网内的 IP。
  String? extractIp(String html) {
    return _v46ip.firstMatch(html)?.group(1) ??
        _v4ip.firstMatch(html)?.group(1);
  }

  /// 从 portal 页面提取注销所需的 mac 地址。
  /// 兼容单引号 / 双引号及等号两侧空白等页面写法差异。
  String? extractMac(String html) =>
      _olmac.firstMatch(html)?.group(1);

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

  Uri buildLogoutUri(String mac) => _eportalUri({
        'c': 'ACSetting',
        'a': 'Logout',
        'wlanuserip': 'null',
        'wlanacip': 'null',
        'wlanacname': 'null',
        'port': '',
        'hostname': config.portalHost,
        'iTermType': '1',
        'session': 'null',
        'queryACIP': '0',
        'mac': mac,
      });

  /// 未拿到 mac 时的备选：以本机 IP 定位会话注销。
  Uri buildLogoutUriByIp(String ip) => _eportalUri({
        'c': 'ACSetting',
        'a': 'Logout',
        'wlanuserip': ip,
        'wlanacip': 'null',
        'wlanacname': 'null',
        'port': '',
        'hostname': config.portalHost,
        'iTermType': '1',
        'session': 'null',
        'queryACIP': '0',
        'mac': '00-00-00-00-00-00',
      });

  Map<String, String> buildLogoutBody({String? mac, String? ip}) => {
        'c': 'ACSetting',
        'a': 'Logout',
        'wlanuserip': ip ?? 'null',
        'wlanacname': 'null',
        'port': '',
        'hostname': config.portalHost,
        'iTermType': '1',
        'session': 'null',
        'queryACIP': '0',
        'mac': mac ?? (ip == null ? '' : '00-00-00-00-00-00'),
      };

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

  /// 发起登录请求。返回是否得到 HTTP 200（不代表认证成功）。
  Future<bool> postLogin({
    required String username,
    required String password,
    Operator operator = Operator.campus,
    bool freeAccess = false,
  }) async {
    final page = await fetchPortalPage();
    final ip = extractIp(page);
    if (ip == null || ip.isEmpty) {
      throw const EportalException('未能从 portal 页面解析到本机 IP');
    }
    final body = buildLoginBody(
      username: username,
      password: password,
      operator: operator,
      freeAccess: freeAccess,
    );
    final res = await _client
        .post(buildLoginUri(ip), headers: requestHeaders, body: body)
        .timeout(config.requestTimeout);
    return res.statusCode == 200;
  }

  /// 注销当前会话。
  ///
  /// 已在线时 portal 首页可能不含有效 olmac，因此按序尝试：
  /// 1. 首页提取 olmac → mac 版注销；
  /// 2. 提取本机 IP → wlanuserip 版注销。
  /// 全部失败时抛出 [EportalException]，message 说明各环节结果。
  Future<bool> logout() async {
    final failures = <String>[];

    String? page;
    try {
      page = await fetchPortalPage();
    } catch (e) {
      throw EportalException('portal 页面获取失败：$e');
    }

    final mac = extractMac(page);
    if (mac != null && mac.isNotEmpty && mac != '00-00-00-00-00-00') {
      try {
        final res = await _client
            .post(
              buildLogoutUri(mac),
              headers: requestHeaders,
              body: buildLogoutBody(mac: mac),
            )
            .timeout(config.requestTimeout);
        if (res.statusCode == 200) return true;
        failures.add('mac版注销 HTTP ${res.statusCode}');
      } catch (e) {
        failures.add('mac版注销异常：$e');
      }
    } else {
      failures.add('首页未提供 olmac（已在线态常见）');
    }

    final ip = extractIp(page);
    if (ip != null && ip.isNotEmpty) {
      try {
        final res = await _client
            .post(
              buildLogoutUriByIp(ip),
              headers: requestHeaders,
              body: buildLogoutBody(ip: ip),
            )
            .timeout(config.requestTimeout);
        if (res.statusCode == 200) return true;
        failures.add('IP版注销 HTTP ${res.statusCode}');
      } catch (e) {
        failures.add('IP版注销异常：$e');
      }
    } else {
      failures.add('首页未解析到本机 IP');
    }

    throw EportalException(failures.join('；'));
  }
}

class EportalException implements Exception {
  const EportalException(this.message);

  final String message;

  @override
  String toString() => 'EportalException: $message';
}
