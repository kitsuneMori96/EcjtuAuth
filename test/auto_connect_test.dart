import 'dart:math';

import 'package:ecjtu_auth/core/eportal_client.dart';
import 'package:ecjtu_auth/core/network_checker.dart';
import 'package:ecjtu_auth/core/portal_failure.dart';
import 'package:ecjtu_auth/models/campus_account.dart';
import 'package:ecjtu_auth/models/net_state.dart';
import 'package:ecjtu_auth/models/operator.dart';
import 'package:ecjtu_auth/services/auto_connect.dart';
import 'package:ecjtu_auth/services/credential_store.dart';
import 'package:ecjtu_auth/services/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 依次返回 [responses] 中各项；String 为页面，PortalException 为请求失败。
/// 超出长度后重复最后一项。
class _FakeEportal extends EportalClient {
  _FakeEportal(this.responses);

  List<Object> responses;
  int fetchCount = 0;
  int loginCount = 0;
  Object? loginError;

  @override
  Future<String> fetchPortalPage() async {
    final index = min(fetchCount, responses.length - 1);
    fetchCount++;
    final item = responses[index];
    if (item is PortalException) throw item;
    return item as String;
  }

  @override
  String? extractIp(String html) => '10.0.0.8';

  @override
  Future<(bool, String)> postLogin({
    required String ip,
    required String username,
    required String password,
    Operator operator = Operator.campus,
    bool freeAccess = false,
  }) async {
    loginCount++;
    if (loginError != null) throw loginError!;
    return (true, 'HTTP 302');
  }
}

class _FakeCredentials extends CredentialStore {
  _FakeCredentials([this.account]);

  CampusAccount? account;

  @override
  Future<CampusAccount?> read() async => account;
}

Future<AutoConnectService> _makeService({
  required _FakeEportal eportal,
  AppSettings settings = const AppSettings(),
  Future<(int, String)?> Function()? fetchLength,
  String? ssid = 'ECJTU-Stu',
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = SettingsStore(prefs);
  await store.save(settings);

  final service = AutoConnectService(
    eportal: eportal,
    checker: NetworkChecker(eportal: eportal),
    credentials: _FakeCredentials(
      const CampusAccount(username: '20230001', password: 'secret'),
    ),
    settings: store,
    currentSsid: () async => ssid,
    fetchLength: fetchLength ?? () async => (100, 'Test'),
  );
  await service.loadSettings();
  return service;
}

const _timeout = PortalException(PortalFailure.timeout, 'GET portal 超时');

void main() {
  group('AutoConnectService', () {
    test('已在线时跳过登录', () async {
      final eportal = _FakeEportal(['x' * 120]);
      final service = await _makeService(
        eportal: eportal,
        settings: const AppSettings(offlinePageLength: 100),
      );

      final outcome = await service.connectNow();

      expect(outcome, ConnectOutcome.alreadyOnline);
      expect(eportal.loginCount, 0);
      expect(service.state, NetState.online);
    });

    test('登录成功后复验在线', () async {
      final eportal = _FakeEportal(['x' * 100, 'x' * 120]);
      final service = await _makeService(
        eportal: eportal,
        settings: const AppSettings(offlinePageLength: 100),
      );

      final outcome = await service.connectNow();

      expect(outcome, ConnectOutcome.success);
      expect(eportal.loginCount, 1);
      expect(service.state, NetState.online);
    });

    test('portal 不可达且无缓存 IP → portalUnreachable，不显示“本就在线”', () async {
      final eportal = _FakeEportal([_timeout]);
      final service = await _makeService(
        eportal: eportal,
        settings: const AppSettings(offlinePageLength: 100),
      );

      final outcome = await service.connectNow();

      expect(outcome, ConnectOutcome.portalUnreachable);
      expect(eportal.loginCount, 0);
      expect(service.state, NetState.campusBlocked);
      expect(service.statusDetail, contains('请求超时'));
    });

    test('非校园 SSID 且 portal 不可达 → notOnCampus', () async {
      final eportal = _FakeEportal([_timeout]);
      final service = await _makeService(
        eportal: eportal,
        settings: const AppSettings(offlinePageLength: 100),
        ssid: 'HomeWifi',
      );

      final outcome = await service.connectNow();

      expect(outcome, ConnectOutcome.notOnCampus);
      expect(service.state, NetState.noCampusWifi);
    });

    test('并发连接共享同一个 in-flight，只登录一次', () async {
      final eportal = _FakeEportal(['x' * 100, 'x' * 120]);
      final service = await _makeService(
        eportal: eportal,
        settings: const AppSettings(offlinePageLength: 100),
      );

      final results = await Future.wait([
        service.connectNow(),
        service.connectNow(),
        service.connectOnce(),
      ]);

      expect(results, everyElement(ConnectOutcome.success));
      expect(eportal.loginCount, 1);
      // 首次获取 + 复验一次，而不是每个调用各走一遍
      expect(eportal.fetchCount, 2);
    });

    test('基准缺失时从仓库拉取并持久化', () async {
      final eportal = _FakeEportal(['x' * 100, 'x' * 120]);
      final service = await _makeService(
        eportal: eportal,
        fetchLength: () async => (100, 'Test'),
      );

      final outcome = await service.connectNow();

      expect(outcome, ConnectOutcome.success);
      final saved = await service.settingsStore.load();
      expect(saved.offlinePageLength, 100);
    });

    test('portal 不可达但已有缓存 IP 时仍尝试登录', () async {
      final eportal = _FakeEportal(['x' * 100, 'x' * 120]);
      final service = await _makeService(
        eportal: eportal,
        settings: const AppSettings(offlinePageLength: 100),
      );
      await service.connectNow();
      expect(eportal.loginCount, 1);

      eportal.responses = [_timeout];
      final outcome = await service.connectNow();

      expect(outcome, ConnectOutcome.portalUnreachable);
      expect(eportal.loginCount, 2);
    });

    test('连续认证失败 3 次后停止自动重试', () async {
      // 基准与页面长度相同 → POST 成功但复验始终离线
      final eportal = _FakeEportal(['x' * 100]);
      final service = await _makeService(
        eportal: eportal,
        settings: const AppSettings(
          offlinePageLength: 100,
          baseRetryDelaySec: 0,
          maxRetryDelaySec: 0,
        ),
      );

      service.startAutoRetry();
      // 每次尝试含 300ms 生效等待 + 500ms 二次验证，3 次约 2.4s
      await Future.delayed(const Duration(seconds: 4));

      expect(
        service.logLines.any((line) => line.contains('连续认证失败 3 次')),
        isTrue,
      );
      final fetchesAtStop = eportal.fetchCount;
      await Future.delayed(const Duration(milliseconds: 300));
      expect(eportal.fetchCount, fetchesAtStop);
      expect(eportal.loginCount, 3);
    });
  });
}
