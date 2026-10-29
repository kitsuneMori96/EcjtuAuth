import 'package:ecjtu_auth/core/eportal_client.dart';
import 'package:ecjtu_auth/core/network_checker.dart';
import 'package:ecjtu_auth/core/portal_failure.dart';
import 'package:ecjtu_auth/models/net_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEportal extends EportalClient {
  _FakeEportal({this.body = '', this.error});

  String body;
  Object? error;
  int fetchCount = 0;

  @override
  Future<String> fetchPortalPage() async {
    fetchCount++;
    if (error != null) throw error!;
    return body;
  }
}

void main() {
  group('NetworkChecker.judge', () {
    test('长度与基准相同 → 待认证', () {
      final checker = NetworkChecker(eportal: _FakeEportal())
        ..offlinePageLength = 10;
      final result = checker.judge('x' * 10);
      expect(result.state, NetState.campusBlocked);
      expect(result.pageLength, 10);
      expect(result.failure, isNull);
      expect(result.needsCalibration, isFalse);
    });

    test('长度不同 → 在线', () {
      final checker = NetworkChecker(eportal: _FakeEportal())
        ..offlinePageLength = 10;
      final result = checker.judge('x' * 11);
      expect(result.state, NetState.online);
    });

    test('未校准 → unknown 且标记 needsCalibration', () {
      final checker = NetworkChecker(eportal: _FakeEportal());
      final result = checker.judge('x' * 10);
      expect(result.state, NetState.unknown);
      expect(result.needsCalibration, isTrue);
    });
  });

  group('NetworkChecker.check', () {
    test('portal 超时 → unknown + timeout，不再误报未连接校园网', () async {
      final fake = _FakeEportal(
        error: const PortalException(PortalFailure.timeout, 'GET portal 超时'),
      );
      final checker = NetworkChecker(eportal: fake)..offlinePageLength = 10;

      final result = await checker.check();

      expect(result.state, NetState.unknown);
      expect(result.failure, PortalFailure.timeout);
    });

    test('传入已获取的页面时不再发请求', () async {
      final fake = _FakeEportal(body: 'x' * 10);
      final checker = NetworkChecker(eportal: fake)..offlinePageLength = 10;

      final result = await checker.check(portalBody: 'x' * 10);

      expect(result.state, NetState.campusBlocked);
      expect(fake.fetchCount, 0);
    });
  });
}
