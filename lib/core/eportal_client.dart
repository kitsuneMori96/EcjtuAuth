import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/operator.dart';
import 'app_config.dart';
import 'portal_failure.dart';

/// Dr.COM eportal 认证协议客户端。
///
/// 协议流程：
/// 1. GET `http://{host}/` 从页面 JS 中提取本机 IP（v46ip / v4ip）；
/// 2. 携带表单向 `http://{host}:801/eportal/?c=ACSetting&a=Login` POST 登录。
///
/// 登录成败以 POST 后的连通性复验为准（见 NetworkChecker），
/// 本类只负责协议交互，不判断结果。
class EportalClient {
  EportalClient({http.Client? client, AppConfig config = const AppConfig()})
    : _client = client ?? http.Client(),
      config = config;

  final http.Client _client;

  /// 运行时配置；设置页保存后更新，下一次请求即使用新地址。
  AppConfig config;

  static final RegExp _v46ip = RegExp(r"""v46ip\s*=\s*['"]([^'"]*)['"]""");
  static final RegExp _v4ip = RegExp(r"""v4ip\s*=\s*['"]([^'"]*)['"]""");

  static const Map<String, String> requestHeaders = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
  };

  Uri get portalUri => Uri.parse('http://${config.portalHost}/');

  Uri _eportalUri(Map<String, String> query) => Uri.http(
    '${config.portalHost}:${AppConfig.portalPort}',
    '/eportal/',
    query,
  );

  /// 拉取 portal 页面原文；失败抛出 [PortalException]。
  ///
  /// 超时/连接类失败会再试一次；HTTP 状态码或空内容不重试。
  Future<String> fetchPortalPage() async {
    PortalException? lastFailure;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _client
            .get(portalUri, headers: requestHeaders)
            .timeout(config.requestTimeout);
        if (res.statusCode != 200) {
          throw PortalException(
            PortalFailure.httpStatus,
            'portal responded ${res.statusCode}',
            statusCode: res.statusCode,
          );
        }
        if (res.body.trim().isEmpty) {
          throw const PortalException(
            PortalFailure.badContent,
            'portal page is empty',
          );
        }
        return res.body;
      } on PortalException catch (e) {
        lastFailure = e;
        if (e.failure == PortalFailure.httpStatus ||
            e.failure == PortalFailure.badContent) {
          rethrow;
        }
      } catch (e) {
        lastFailure = _classify(e, 'GET portal');
      }
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    throw lastFailure ??
        const PortalException(PortalFailure.unknown, 'portal fetch failed');
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

  /// 发起登录请求。返回 (httpOk, detail)；网络/HTTP 失败抛出 [PortalException]。
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
    try {
      final res = await _client
          .post(uri, headers: requestHeaders, body: body)
          .timeout(config.requestTimeout);
      final snippet = _snippet(res.body);
      final detail =
          'HTTP ${res.statusCode} | url=$uri | '
          'DDDDD=${body['DDDDD']} | resp=$snippet';
      if (res.statusCode < 200 || res.statusCode >= 400) {
        throw PortalException(
          PortalFailure.httpStatus,
          detail,
          statusCode: res.statusCode,
        );
      }
      return (true, detail);
    } on PortalException {
      rethrow;
    } catch (e) {
      throw _classify(e, 'POST 登录');
    }
  }

  PortalException _classify(Object error, String action) {
    if (error is PortalException) return error;
    if (error is TimeoutException) {
      return PortalException(
        PortalFailure.timeout,
        '$action 超过 ${config.requestTimeout.inSeconds}s',
      );
    }
    if (error is SocketException) {
      final code = error.osError?.errorCode;
      final message = error.osError?.message ?? error.message;
      final refused =
          code == 111 ||
          code == 10061 ||
          message.toLowerCase().contains('refused');
      return PortalException(
        refused ? PortalFailure.refused : PortalFailure.unreachable,
        '$action 失败: $message',
      );
    }
    if (error is http.ClientException) {
      return PortalException(
        PortalFailure.unreachable,
        '$action 失败: ${error.message}',
      );
    }
    return PortalException(PortalFailure.unknown, '$action 失败: $error');
  }

  String _snippet(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > 200 ? flat.substring(0, 200) : flat;
  }
}
