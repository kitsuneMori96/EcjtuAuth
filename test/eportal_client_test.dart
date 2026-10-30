import 'dart:io';

import 'package:ecjtu_auth/core/app_config.dart';
import 'package:ecjtu_auth/core/eportal_client.dart';
import 'package:ecjtu_auth/core/portal_failure.dart';
import 'package:ecjtu_auth/models/operator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const fakePortalHtml = '''
<html><head></head>
<script>
var v46ip='10.30.66.77 ';
var v4ip='';
</script></html>
''';

const fakePortalHtmlV4 = '''
<script>var v4ip='192.168.5.5';</script>
''';

http.Response _ok([String body = 'ok']) =>
    http.Response(body, 200, headers: {'content-type': 'text/html'});

EportalClient clientWith(
  Future<http.Response> Function(http.Request req) handler, {
  Duration timeout = const Duration(seconds: 3),
}) {
  return EportalClient(
    config: AppConfig(portalHost: '172.16.2.100', requestTimeout: timeout),
    client: MockClient((req) => handler(req)),
  );
}

Matcher throwsPortalFailure(PortalFailure failure) => throwsA(
  isA<PortalException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  group('extractIp', () {
    test('解析 v46ip（自动 trim 尾部空格）', () {
      final c = EportalClient();
      expect(c.extractIp(fakePortalHtml), '10.30.66.77');
    });

    test('v46ip 缺失时回退 v4ip', () {
      final c = EportalClient();
      expect(c.extractIp(fakePortalHtmlV4), '192.168.5.5');
    });

    test('支持双引号包裹', () {
      final c = EportalClient();
      expect(c.extractIp('<script>var v4ip="10.1.2.3";</script>'), '10.1.2.3');
    });

    test('都缺失时返回 null', () {
      final c = EportalClient();
      expect(c.extractIp('<html></html>'), isNull);
    });
  });

  group('buildLoginBody', () {
    final c = EportalClient();

    test('校园网账号不带后缀', () {
      final body = c.buildLoginBody(username: '20230001', password: 'pw');
      expect(body['DDDDD'], ',0,20230001');
      expect(body['upass'], 'pw');
      expect(body['0MKKey'], '123456');
    });

    test('运营商后缀拼接', () {
      expect(
        c.buildLoginBody(
          username: 'u1',
          password: 'p',
          operator: Operator.cmcc,
        )['DDDDD'],
        ',0,u1@cmcc',
      );
      expect(
        c.buildLoginBody(
          username: 'u1',
          password: 'p',
          operator: Operator.telecom,
        )['DDDDD'],
        ',0,u1@telecom',
      );
      expect(
        c.buildLoginBody(
          username: 'u1',
          password: 'p',
          operator: Operator.unicom,
        )['DDDDD'],
        ',0,u1@unicom',
      );
    });

    test('图书馆免费网络不带运营商', () {
      final body = c.buildLoginBody(
        username: 'u1',
        password: 'p',
        operator: Operator.cmcc,
        freeAccess: true,
      );
      expect(body['DDDDD'], ',0,u1');
    });
  });

  group('postLogin', () {
    test('使用传入的 IP 发送登录表单', () async {
      final bodies = <Map<String, String>>[];
      final c = clientWith((req) async {
        expect(req.url.toString(), contains('a=Login'));
        expect(req.url.toString(), contains('wlanuserip=10.30.66.77'));
        expect(req.url.toString(), isNot(contains(' ')));
        bodies.add(req.bodyFields);
        return _ok();
      });

      final (ok, detail) = await c.postLogin(
        ip: '10.30.66.77',
        username: 'stu001',
        password: 'secret',
        operator: Operator.cmcc,
      );

      expect(ok, isTrue);
      expect(detail, contains('DDDDD=,0,stu001@cmcc'));
      expect(bodies.single['DDDDD'], ',0,stu001@cmcc');
      expect(bodies.single['upass'], 'secret');
    });

    test('302 重定向视为成功', () async {
      final c = clientWith(
        (req) async => http.Response('', 302, headers: {'location': '/'}),
      );
      final (ok, _) = await c.postLogin(
        ip: '10.0.0.1',
        username: 'u',
        password: 'p',
      );
      expect(ok, isTrue);
    });

    test('HTTP 500 → httpStatus 分类', () async {
      final c = clientWith((req) async => http.Response('bad', 500));
      await expectLater(
        c.postLogin(ip: '10.0.0.1', username: 'u', password: 'p'),
        throwsPortalFailure(PortalFailure.httpStatus),
      );
    });
  });

  group('portal 请求失败分类', () {
    test('超时 → timeout', () async {
      final c = clientWith((req) async {
        await Future.delayed(const Duration(milliseconds: 300));
        return _ok();
      }, timeout: const Duration(milliseconds: 20));
      await expectLater(
        c.fetchPortalPage(),
        throwsPortalFailure(PortalFailure.timeout),
      );
    });

    test('连接被拒绝 → refused', () async {
      final c = clientWith(
        (req) async => throw SocketException(
          'Connection refused',
          osError: const OSError('Connection refused', 111),
        ),
      );
      await expectLater(
        c.fetchPortalPage(),
        throwsPortalFailure(PortalFailure.refused),
      );
    });

    test('ClientException 文本含 refused → refused', () async {
      final c = clientWith(
        (req) async =>
            throw http.ClientException('Connection refused (errno = 111)'),
      );
      await expectLater(
        c.fetchPortalPage(),
        throwsPortalFailure(PortalFailure.refused),
      );
    });

    test('ClientException 无 refused 文本 → unreachable（非 unknown）', () async {
      final c = clientWith(
        (req) async => throw http.ClientException('Connection closed before '
            'full header was received'),
      );
      await expectLater(
        c.fetchPortalPage(),
        throwsPortalFailure(PortalFailure.unreachable),
      );
    });

    test('HTTP 500 → httpStatus（不重试）', () async {
      var calls = 0;
      final c = clientWith((req) async {
        calls++;
        return http.Response('oops', 500);
      });
      await expectLater(
        c.fetchPortalPage(),
        throwsPortalFailure(PortalFailure.httpStatus),
      );
      expect(calls, 1);
    });

    test('空响应 → badContent', () async {
      final c = clientWith((req) async => http.Response('   \n', 200));
      await expectLater(
        c.fetchPortalPage(),
        throwsPortalFailure(PortalFailure.badContent),
      );
    });
  });

  group('运行时配置', () {
    test('修改 config 后请求使用新 host', () {
      final c = EportalClient();
      c.config = const AppConfig(portalHost: '10.9.9.9');
      expect(c.portalUri.host, '10.9.9.9');
      final loginUri = c.buildLoginUri('1.2.3.4');
      expect(loginUri.host, '10.9.9.9');
      expect(loginUri.port, 801);
    });
  });
}
