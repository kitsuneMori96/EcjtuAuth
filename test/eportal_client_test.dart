import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:auin_ecjtu_wifi/core/app_config.dart';
import 'package:auin_ecjtu_wifi/core/eportal_client.dart';
import 'package:auin_ecjtu_wifi/models/operator.dart';

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

const fakePortalHtmlMac = """
<html><script>olmac='AA-BB-CC-DD-EE-FF';</script></html>
""";

http.Response _ok([String body = 'ok']) =>
    http.Response(body, 200, headers: {'content-type': 'text/html'});

EportalClient clientWith(
    Future<http.Response> Function(http.Request req) handler) {
  return EportalClient(
    config: const AppConfig(portalHost: '172.16.2.100'),
    client: MockClient((req) => handler(req)),
  );
}

void main() {
  group('extractIp', () {
    test('解析 v46ip', () {
      final c = EportalClient();
      expect(c.extractIp(fakePortalHtml), '10.30.66.77 ');
    });

    test('v46ip 缺失时回退 v4ip', () {
      final c = EportalClient();
      expect(c.extractIp(fakePortalHtmlV4), '192.168.5.5');
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
        c
            .buildLoginBody(username: 'u1', password: 'p', operator: Operator.cmcc)
            ['DDDDD'],
        ',0,u1@cmcc',
      );
      expect(
        c
            .buildLoginBody(
                username: 'u1', password: 'p', operator: Operator.telecom)
            ['DDDDD'],
        ',0,u1@telecom',
      );
      expect(
        c
            .buildLoginBody(
                username: 'u1', password: 'p', operator: Operator.unicom)
            ['DDDDD'],
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

  group('buildLoginUri / buildLogoutUri', () {
    test('登录 URL 携带 IP 与主机参数', () {
      final uri =
          EportalClient().buildLoginUri('10.0.0.9').toString();
      expect(uri, contains('c=ACSetting'));
      expect(uri, contains('a=Login'));
      expect(uri, contains(':801/eportal/'));
      expect(uri, contains('wlanuserip=10.0.0.9'));
      expect(uri, contains('hostname=172.16.2.100'));
    });

    test('注销 URL 携带 mac', () {
      final uri = EportalClient()
          .buildLogoutUri('AA-BB-CC')
          .toString();
      expect(uri, contains('a=Logout'));
      expect(uri, contains('mac=AA-BB-CC'));
    });
  });

  group('postLogin', () {
    test('先取 portal 再 POST 登录表单', () async {
      final bodies = <Map<String, String>>[];
      var step = 0;
      final c = clientWith((req) async {
        if (step == 0) {
          step += 1;
          return _ok(fakePortalHtml);
        }
        expect(req.url.toString(), contains('a=Login'));
        expect(req.url.toString(), contains('wlanuserip=10.30.66.77'));
        bodies.add(req.bodyFields);
        return _ok();
      });

      final ok = await c.postLogin(
        username: 'stu001',
        password: 'secret',
        operator: Operator.cmcc,
      );

      expect(ok, isTrue);
      expect(bodies.single['DDDDD'], ',0,stu001@cmcc');
      expect(bodies.single['upass'], 'secret');
    });

    test('portal 无 IP 时抛出异常', () async {
      final c = clientWith((req) async => _ok('<html/>'));
      expect(
        () => c.postLogin(username: 'u', password: 'p'),
        throwsA(isA<EportalException>()),
      );
    });
  });

  group('logout', () {
    test('提取 olmac 后 POST 注销', () async {
      Uri? captured;
      final c = clientWith((req) async {
        if (req.url.path.contains('eportal') && req.method == 'POST') {
          captured = req.url;
        } else {
          return _ok(fakePortalHtmlMac);
        }
        return _ok();
      });

      final (ok, detail) = await c.logout();

      expect(ok, isTrue);
      expect(detail, contains('mac版'));
      expect(captured.toString(), contains('mac=AA-BB-CC-DD-EE-FF'));
    });

    test('olmac 双引号写法也能提取', () {
      final c = EportalClient();
      expect(
        c.extractMac('<script>olmac = "AA-BB-CC";</script>'),
        'AA-BB-CC',
      );
    });

    test('注销接口返回 203 视为 HTTP 成功且响应体可见', () async {
      final c = clientWith((req) async {
        if (req.method == 'POST') return http.Response('{"error":"ok"}', 203);
        return _ok(fakePortalHtmlMac);
      });

      final (ok, detail) = await c.logout();

      expect(ok, isTrue);
      expect(detail, contains('203'));
      expect(detail, contains('"error":"ok"'));
    });

    test('首页无 olmac 时回退 IP 版注销', () async {
      final posts = <Uri>[];
      final c = clientWith((req) async {
        if (req.method == 'POST') {
          posts.add(req.url);
          return _ok();
        }
        return _ok("<script>var v46ip='10.1.2.3'</script>");
      });

      final (ok, detail) = await c.logout();

      expect(ok, isTrue);
      expect(detail, contains('IP版'));
      expect(posts, hasLength(1));
      expect(posts.single.toString(), contains('wlanuserip=10.1.2.3'));
      expect(posts.single.toString(), contains('a=Logout'));
    });

    test('两种策略都失败时抛出带原因的异常', () async {
      final c = clientWith((req) async => _ok('<html></html>'));
      try {
        await c.logout();
        fail('should throw');
      } on EportalException catch (e) {
        expect(e.message, contains('olmac'));
        expect(e.message, contains('IP'));
      }
    });
  });
}
