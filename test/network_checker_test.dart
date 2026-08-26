import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:auin_ecjtu_wifi/core/app_config.dart';
import 'package:auin_ecjtu_wifi/core/network_checker.dart';
import 'package:auin_ecjtu_wifi/models/net_state.dart';

const portalHtml = "<script>var v46ip='1.2.3.4'</script>";

NetworkChecker checkerWith({
  Future<http.Response> Function(Uri uri)? onGet,
}) {
  return NetworkChecker(
    config: AppConfig(probeUrls: ['https://probe.example/x']),
    client: MockClient((req) async {
      final res = await onGet!(req.url);
      return http.Response(res.body, res.statusCode);
    }),
  );
}
void main() {
  test('portal 不可达 → noCampusWifi', () async {
    final c = checkerWith(
      onGet: (_) => throw http.ClientException('unreachable'),
    );
    expect(await c.check(), NetState.noCampusWifi);
  });

  test('portal 可达且外网可达（非空 body）→ online', () async {
    final c = checkerWith(
        onGet: (_) async => http.Response('OK', 200));
    expect(await c.check(), NetState.online);
  });

  test('portal 可达但外网返回空 body → campusBlocked', () async {
    final c = checkerWith(onGet: (_) async => http.Response('', 200));
    expect(await c.check(), NetState.campusBlocked);
  });

  test('captive portal 劫持返回 200+HTML → campusBlocked', () async {
    final c = checkerWith(
      onGet: (uri) async {
        if (uri.host == 'probe.example') {
          return http.Response('<html><body>portal</body></html>', 200);
        }
        return http.Response(portalHtml, 200);
      },
    );
    expect(await c.check(), NetState.campusBlocked);
  });

  test('generate_204 URL 返回 200（非 204）→ campusBlocked', () async {
    final c = NetworkChecker(
      config: AppConfig(probeUrls: [
        'http://connect.rom.miui.com/generate_204',
      ]),
      client: MockClient((req) async {
        if (req.url.host == 'connect.rom.miui.com') {
          return http.Response('<html>portal</html>', 200);
        }
        return http.Response(portalHtml, 200);
      }),
    );
    expect(await c.check(), NetState.campusBlocked);
  });

  test('generate_204 URL 返回 204 → online', () async {
    final c = NetworkChecker(
      config: AppConfig(probeUrls: [
        'http://connect.rom.miui.com/generate_204',
      ]),
      client: MockClient((req) async {
        if (req.url.host == 'connect.rom.miui.com') {
          return http.Response('', 204);
        }
        return http.Response(portalHtml, 200);
      }),
    );
    expect(await c.check(), NetState.online);
  });

  test('portal 可达但外网不可达 → campusBlocked', () async {
    final c = checkerWith(
      onGet: (uri) async {
        if (uri.host == 'probe.example') {
          throw http.ClientException('blocked');
        }
        return http.Response(portalHtml, 200);
      },
    );
    expect(await c.check(), NetState.campusBlocked);
  });

  test('外网返回异常状态码视为被墙/未认证 → campusBlocked', () async {
    final c = checkerWith(
      onGet: (uri) async => uri.host == 'probe.example'
          ? http.Response('', 302)
          : http.Response(portalHtml, 200),
    );
    expect(await c.check(), NetState.campusBlocked);
  });
}
