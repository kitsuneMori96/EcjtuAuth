import 'dart:async';
import 'dart:math';

import 'package:ecjtu_auth/core/eportal_client.dart';
import 'package:ecjtu_auth/core/network_checker.dart';
import 'package:ecjtu_auth/core/portal_failure.dart';
import 'package:ecjtu_auth/models/campus_account.dart';
import 'package:ecjtu_auth/models/net_state.dart';
import 'package:ecjtu_auth/models/operator.dart';
import 'package:ecjtu_auth/platform/nlm_service.dart';
import 'package:ecjtu_auth/services/auto_connect.dart';
import 'package:ecjtu_auth/services/credential_store.dart';
import 'package:ecjtu_auth/services/settings_store.dart';
import 'package:fake_async/fake_async.dart';
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

class _FakeNlm extends NlmService {
  _FakeNlm([this.network]) : super(supportedPlatform: true);

  /// null 表示平台通道不可用（老原生包），调用方应回退旧行为。
  CurrentNetwork? network;

  final _controller = StreamController<NlmNetworkEvent>.broadcast();

  @override
  Stream<NlmNetworkEvent> get onNetworkChanged => _controller.stream;

  @override
  Future<CurrentNetwork?> currentNetwork() async => network;

  void emit(
    String event, [
    String ssid = '',
    NetworkType type = NetworkType.unknown,
  ]) => _controller.add(
    NlmNetworkEvent(event: event, ssid: ssid, type: type),
  );
}

class _FakeCredentials extends CredentialStore {
  _FakeCredentials([this.account]);

  CampusAccount? account;

  @override
  Future<CampusAccount?> read() async => account;
}

const _testAccount = CampusAccount(username: '20230001', password: 'secret');

Future<AutoConnectService> _makeService({
  required _FakeEportal eportal,
  AppSettings settings = const AppSettings(),
  Future<(int, String)?> Function()? fetchLength,
  String? ssid = 'ECJTU-Stu',
  NlmService? nlmService,
  CampusAccount? account = _testAccount,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = SettingsStore(prefs);
  await store.save(settings);

  final service = AutoConnectService(
    eportal: eportal,
    checker: NetworkChecker(eportal: eportal),
    credentials: _FakeCredentials(account),
    settings: store,
    nlmService: nlmService,
    currentSsid: () async => ssid,
    fetchLength: fetchLength ?? () async => (100, 'Test'),
  );
  await service.loadSettings();
  return service;
}

/// fakeAsync 里不能直接 await，只能把微任务推动到结束。
AutoConnectService _makeServiceSync(
  FakeAsync async, {
  required _FakeEportal eportal,
  AppSettings settings = const AppSettings(),
  NlmService? nlmService,
  String? ssid = 'ECJTU-Stu',
  CampusAccount? account = _testAccount,
}) {
  late AutoConnectService service;
  _makeService(
    eportal: eportal,
    settings: settings,
    nlmService: nlmService,
    ssid: ssid,
    account: account,
  ).then((s) => service = s);
  async.flushMicrotasks();
  return service;
}

const _timeout = PortalException(PortalFailure.timeout, 'GET portal 超时');

/// 自动检查是否应该真的发起 portal 请求：账号缺失或明确的蜂窝/断网都不该发。
class _Case {
  const _Case(
    this.type, {
    required this.hasAccount,
    required this.manual,
    required this.outcome,
  });

  /// null 表示平台通道不可用（老原生包）。
  final NetworkType? type;
  final bool hasAccount;
  final bool manual;
  final ConnectOutcome outcome;

  bool get expectsRequest {
    if (!hasAccount) return false;
    if (manual) return true;
    return type != NetworkType.cellular && type != NetworkType.none;
  }

  @override
  String toString() =>
      '${type?.name ?? 'channel-null'} / ${hasAccount ? '有账号' : '无账号'} / '
      '${manual ? '手动' : '自动'}';
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) fail('等待条件超时');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

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

    test('WiFi 断开事件不直接判定为无校园网，而是重新探测', () async {
      final nlm = _FakeNlm();
      final eportal = _FakeEportal(['x' * 100]);
      final service = await _makeService(
        eportal: eportal,
        nlmService: nlm,
        settings: const AppSettings(offlinePageLength: 100),
      );

      nlm.emit('disconnected');
      await Future.delayed(Duration.zero);
      await pumpEventQueue();

      // 断开 WiFi 仍可能走以太网，不能直接落到「未连接校园网」
      expect(service.state, isNot(NetState.noCampusWifi));
      expect(eportal.fetchCount, greaterThan(0));
    });

    test('网络事件带回的 SSID 立即可读', () async {
      final nlm = _FakeNlm();
      final service = await _makeService(
        eportal: _FakeEportal(['x' * 100]),
        nlmService: nlm,
        settings: const AppSettings(offlinePageLength: 100),
      );
      expect(service.lastSsid, isNull);

      nlm.emit('connected', '"ECJTU-Stu"');
      await pumpEventQueue();

      expect(service.lastSsid, 'ECJTU-Stu');
    });

    test('未配置账号：不认证、不排重试，提示去账号页', () async {
      final eportal = _FakeEportal(['x' * 100]);
      final service = await _makeService(
        eportal: eportal,
        account: null,
        settings: const AppSettings(
          offlinePageLength: 100,
          baseRetryDelaySec: 0,
          maxRetryDelaySec: 0,
        ),
      );

      final outcome = await service.connectNow();
      expect(outcome, ConnectOutcome.noAccount);
      expect(eportal.loginCount, 0);
      expect(eportal.fetchCount, 0);
      expect(service.statusDetail, contains('账号'));

      service.startAutoRetry();
      await Future.delayed(const Duration(milliseconds: 300));

      expect(
        service.logLines.any((line) => line.contains('已停止自动重试')),
        isTrue,
      );
      expect(
        service.logLines.any((line) => line.contains('后重试')),
        isFalse,
        reason: '缺账号重试毫无意义',
      );
      service.dispose();
    });

    test('换网事件清零连续失败计数', () async {
      final eportal = _FakeEportal(['x' * 100]);
      final nlm = _FakeNlm();
      final service = await _makeService(
        eportal: eportal,
        ssid: '',
        nlmService: nlm,
        settings: const AppSettings(
          offlinePageLength: 100,
          baseRetryDelaySec: 0,
          maxRetryDelaySec: 0,
        ),
      );

      // 蜂窝上先失败 2 次（ssid 为空）
      service.startAutoRetry();
      await _waitUntil(() => service.authFailStreak >= 2);
      expect(service.authFailStreak, greaterThanOrEqualTo(2));

      // 切回校园网
      nlm.emit('connected', 'ECJTU-Stu');
      await pumpEventQueue();

      expect(service.logLines.any((line) => line.contains('重置连续失败计数')), isTrue);
      expect(service.authFailStreak, lessThan(2));
      service.dispose();
    });

    test('检查入口记录触发来源', () async {
      final eportal = _FakeEportal(['x' * 100]);
      final nlm = _FakeNlm();
      final service = await _makeService(
        eportal: eportal,
        nlmService: nlm,
        settings: const AppSettings(
          offlinePageLength: 100,
          baseRetryDelaySec: 0,
          maxRetryDelaySec: 0,
        ),
      );

      await service.connectNow(source: 'manual');
      expect(service.logLines.any((line) => line.contains('来源: manual')), isTrue);

      nlm.emit('connected', 'ECJTU-Stu');
      await pumpEventQueue();
      expect(
        service.logLines.any((line) => line.contains('event')),
        isTrue,
        reason: '锁屏期间的检查要能说清是谁触发的',
      );
      service.dispose();
    });

    test('蜂窝网络不发起认证，手动认证强制覆盖', () async {
      final eportal = _FakeEportal(['x' * 100]);
      final nlm = _FakeNlm(
        const CurrentNetwork(
          type: NetworkType.cellular,
          ssid: '',
          ssidVisible: false,
        ),
      );
      final service = await _makeService(
        eportal: eportal,
        nlmService: nlm,
        settings: const AppSettings(offlinePageLength: 100),
      );

      final outcome = await service.connectOnce();
      expect(outcome, ConnectOutcome.notOnCampus);
      expect(eportal.fetchCount, 0);
      expect(service.state, NetState.noCampusWifi);

      // 一键认证不看网络类型（VPN 等场景下蜂窝也能访问 portal）
      await service.connectNow();
      expect(eportal.fetchCount, greaterThan(0));
      expect(eportal.loginCount, 1);
    });

    test('蜂窝上不排重试', () async {
      final eportal = _FakeEportal(['x' * 100]);
      final nlm = _FakeNlm(
        const CurrentNetwork(
          type: NetworkType.cellular,
          ssid: '',
          ssidVisible: false,
        ),
      );
      final service = await _makeService(
        eportal: eportal,
        nlmService: nlm,
        settings: const AppSettings(
          offlinePageLength: 100,
          baseRetryDelaySec: 0,
          maxRetryDelaySec: 0,
        ),
      );

      service.startAutoRetry();
      await _waitUntil(
        () => service.logLines.any((line) => line.contains('暂停自动重试')),
      );
      expect(service.logLines.any((line) => line.contains('后重试')), isFalse);
      service.dispose();
    });

    test('portal 连续不可达 5 次后停止重试', () async {
      final eportal = _FakeEportal([_timeout]);
      final service = await _makeService(
        eportal: eportal,
        settings: const AppSettings(
          offlinePageLength: 100,
          baseRetryDelaySec: 0,
          maxRetryDelaySec: 0,
        ),
      );

      service.startAutoRetry();
      await _waitUntil(
        () => service.logLines.any((line) => line.contains('连续 5 次不可达')),
      );
      expect(service.statusDetail, contains('代理'));

      final fetches = eportal.fetchCount;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(eportal.fetchCount, fetches);
      service.dispose();
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
      expect(service.logLines.any((line) => line.contains('来源: retry')), isTrue);
      final fetchesAtStop = eportal.fetchCount;
      await Future.delayed(const Duration(milliseconds: 300));
      expect(eportal.fetchCount, fetchesAtStop);
      expect(eportal.loginCount, 3);
    });
  });

  group('状态矩阵（网络类型 × 账号 × 入口）', () {
    const cases = [
      _Case(
        NetworkType.wifi,
        hasAccount: true,
        manual: false,
        outcome: ConnectOutcome.success,
      ),
      _Case(
        NetworkType.wifi,
        hasAccount: true,
        manual: true,
        outcome: ConnectOutcome.success,
      ),
      _Case(
        NetworkType.ethernet,
        hasAccount: true,
        manual: false,
        outcome: ConnectOutcome.success,
      ),
      // unknown = 老原生包（通道无 type），必须保持旧行为：照常认证。
      _Case(
        NetworkType.unknown,
        hasAccount: true,
        manual: false,
        outcome: ConnectOutcome.success,
      ),
      _Case(
        null,
        hasAccount: true,
        manual: false,
        outcome: ConnectOutcome.success,
      ),
      _Case(
        NetworkType.cellular,
        hasAccount: true,
        manual: false,
        outcome: ConnectOutcome.notOnCampus,
      ),
      _Case(
        NetworkType.none,
        hasAccount: true,
        manual: false,
        outcome: ConnectOutcome.notOnCampus,
      ),
      // 手动一键认证不看网络类型（VPN 场景），蜂窝上也照发。
      _Case(
        NetworkType.cellular,
        hasAccount: true,
        manual: true,
        outcome: ConnectOutcome.success,
      ),
      _Case(
        NetworkType.none,
        hasAccount: true,
        manual: true,
        outcome: ConnectOutcome.success,
      ),
      _Case(
        NetworkType.cellular,
        hasAccount: false,
        manual: false,
        outcome: ConnectOutcome.noAccount,
      ),
      _Case(
        NetworkType.wifi,
        hasAccount: false,
        manual: true,
        outcome: ConnectOutcome.noAccount,
      ),
    ];

    for (final c in cases) {
      test('$c → ${c.outcome.name}', () async {
        final eportal = _FakeEportal(['x' * 100, 'x' * 120]);
        final nlm = _FakeNlm(
          c.type == null
              ? null
              : CurrentNetwork(type: c.type!, ssid: '', ssidVisible: false),
        );
        final service = await _makeService(
          eportal: eportal,
          nlmService: nlm,
          account: c.hasAccount ? _testAccount : null,
          settings: const AppSettings(offlinePageLength: 100),
        );

        final outcome = c.manual
            ? await service.connectNow(source: 'manual')
            : await service.connectOnce();

        expect(outcome, c.outcome, reason: '$c');
        expect(
          eportal.fetchCount,
          c.expectsRequest ? greaterThan(0) : 0,
          reason: '$c: portal 请求次数',
        );
        expect(
          eportal.loginCount,
          c.expectsRequest ? 1 : 0,
          reason: '$c: 登录次数',
        );
        if (c.outcome == ConnectOutcome.notOnCampus) {
          expect(service.state, NetState.noCampusWifi, reason: '$c');
        }
        service.dispose();
      });
    }
  });

  group('退避时序（fakeAsync）', () {
    const fastSettings = AppSettings(
      offlinePageLength: 100,
      baseRetryDelaySec: 10,
      maxRetryDelaySec: 60,
    );

    test('10s → 20s → 40s → 60s，第 5 次不可达后停止', () {
      fakeAsync((async) {
        final eportal = _FakeEportal([_timeout]);
        final service = _makeServiceSync(
          async,
          eportal: eportal,
          settings: fastSettings,
        );

        service.startAutoRetry();
        async.flushMicrotasks();
        expect(eportal.fetchCount, 1, reason: '首次检查应立刻发生');

        async.elapse(const Duration(seconds: 9));
        expect(eportal.fetchCount, 1, reason: '未到 10s 不应重试');
        async.elapse(const Duration(seconds: 1));
        expect(eportal.fetchCount, 2);

        async.elapse(const Duration(seconds: 19));
        expect(eportal.fetchCount, 2, reason: '第二次间隔应为 20s');
        async.elapse(const Duration(seconds: 1));
        expect(eportal.fetchCount, 3);

        async.elapse(const Duration(seconds: 39));
        expect(eportal.fetchCount, 3, reason: '第三次间隔应为 40s');
        async.elapse(const Duration(seconds: 1));
        expect(eportal.fetchCount, 4);

        async.elapse(const Duration(seconds: 59));
        expect(eportal.fetchCount, 4, reason: '第四次间隔封顶 60s');
        async.elapse(const Duration(seconds: 1));
        expect(eportal.fetchCount, 5);

        // 第 5 次已达 maxTransportRetries，计时器不再续约
        async.elapse(const Duration(minutes: 10));
        expect(eportal.fetchCount, 5);
        expect(
          service.logLines.any((line) => line.contains('连续 5 次不可达')),
          isTrue,
        );
        service.dispose();
      });
    });

    test('换网事件把退避拉回初始间隔', () {
      fakeAsync((async) {
        final eportal = _FakeEportal([_timeout]);
        final nlm = _FakeNlm(
          const CurrentNetwork(
            type: NetworkType.wifi,
            ssid: '',
            ssidVisible: false,
          ),
        );
        final service = _makeServiceSync(
          async,
          eportal: eportal,
          nlmService: nlm,
          settings: fastSettings,
        );

        service.startAutoRetry();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(eportal.fetchCount, 2);
        async.elapse(const Duration(seconds: 20));
        expect(eportal.fetchCount, 3, reason: '此时已进入 20s 档');

        nlm.emit('connected', 'ECJTU-New', NetworkType.wifi);
        async.flushMicrotasks();
        expect(eportal.fetchCount, 4, reason: '换网后立即检查一次');
        expect(
          service.logLines.any((line) => line.contains('type=wifi')),
          isTrue,
          reason: '日志要能看出事件里的网络类型',
        );

        async.elapse(const Duration(seconds: 9));
        expect(eportal.fetchCount, 4, reason: '重新从 10s 起步，而不是 40s');
        async.elapse(const Duration(seconds: 1));
        expect(eportal.fetchCount, 5);
        service.dispose();
      });
    });
  });
}
