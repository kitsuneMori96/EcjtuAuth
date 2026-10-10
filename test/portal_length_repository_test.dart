import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ecjtu_auth/core/portal_length_repository.dart';

/// 按 host 路由的 MockClient，同时记录各源被请求次数。
MockClient mockRouter(
  Map<String, http.Response> byHost, {
  Map<String, int>? hits,
  Map<String, Duration>? delays,
  Set<String>? throwsOn,
}) {
  return MockClient((req) async {
    final host = req.url.host;
    hits?[host] = (hits?[host] ?? 0) + 1;
    if (throwsOn?.contains(host) ?? false) {
      throw http.ClientException('mock network error', req.url);
    }
    final delay = delays?[host];
    if (delay != null) await Future.delayed(delay);
    final res = byHost[host];
    if (res == null) return http.Response('not found', 404);
    return res;
  });
}

http.Response ok([String body = '3661']) => http.Response(body, 200);

void main() {
  group('PortalLengthRepository.fetch', () {
    test('U1: Gitee 命中，不请求 GitHub', () async {
      final hits = <String, int>{};
      final client = mockRouter(
        {'gitee.com': ok(), 'raw.githubusercontent.com': ok('9999')},
        hits: hits,
      );
      final result = await PortalLengthRepository.fetch(client: client);
      expect(result, (3661, 'Gitee'));
      expect(hits['gitee.com'], 1);
      expect(hits['raw.githubusercontent.com'], isNull);
    });

    test('U2: Gitee 非 200，回退 GitHub', () async {
      final client = mockRouter({
        'gitee.com': http.Response('error', 500),
        'raw.githubusercontent.com': ok(),
      });
      final result = await PortalLengthRepository.fetch(client: client);
      expect(result, (3661, 'GitHub'));
    });

    test('U3: Gitee 抛异常，回退 GitHub', () async {
      final client = mockRouter(
        {'raw.githubusercontent.com': ok()},
        throwsOn: {'gitee.com'},
      );
      final result = await PortalLengthRepository.fetch(client: client);
      expect(result, (3661, 'GitHub'));
    });

    test('U4: Gitee 内容非法，跳过并回退', () async {
      for (final bad in ['abc', '-5', '0', '']) {
        final client = mockRouter({
          'gitee.com': ok(bad),
          'raw.githubusercontent.com': ok(),
        });
        final result = await PortalLengthRepository.fetch(client: client);
        expect(result, (3661, 'GitHub'), reason: 'body=$bad');
      }
    });

    test('U5: 双源皆败返回 null', () async {
      final client = mockRouter(
        {'gitee.com': http.Response('e', 500)},
        throwsOn: {'raw.githubusercontent.com'},
      );
      expect(await PortalLengthRepository.fetch(client: client), isNull);

      final client2 = mockRouter(
        {'raw.githubusercontent.com': http.Response('e', 500)},
        throwsOn: {'gitee.com'},
      );
      expect(await PortalLengthRepository.fetch(client: client2), isNull);
    });

    test('U6: 每源超时独立生效', () async {
      final client = mockRouter(
        {
          'gitee.com': ok(),
          'raw.githubusercontent.com': ok(),
        },
        delays: {'gitee.com': const Duration(milliseconds: 300)},
      );
      final result = await PortalLengthRepository.fetch(
        client: client,
        timeout: const Duration(milliseconds: 50),
      );
      expect(result, (3661, 'GitHub'));
    });

    test('U7: 首尾空白容忍', () async {
      final client = mockRouter({'gitee.com': ok('  3661\n')});
      final result = await PortalLengthRepository.fetch(client: client);
      expect(result, (3661, 'Gitee'));
    });

    test('U8: URL 常量回归', () {
      expect(PortalLengthRepository.giteeUrl,
          contains('gitee.com/kitsuneMori/EcjtuAuth-portal'));
      expect(PortalLengthRepository.githubUrl,
          contains('raw.githubusercontent.com/kitsuneMori96/EcjtuAuth'));
      for (final u in [
        PortalLengthRepository.giteeUrl,
        PortalLengthRepository.githubUrl
      ]) {
        expect(u, endsWith('portal_length.txt'));
      }
    });
  });
}
