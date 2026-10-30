import 'package:ecjtu_auth/platform/nlm_service.dart';
import 'package:ecjtu_auth/platform/wifi_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 覆盖平台通道契约与 SSID 单源逻辑：
/// - 事件/查询载荷里的 `type`（区分蜂窝与 WiFi、区分「没 WiFi」与「读不到名字」）
/// - 老原生实现（无 `type` / 无 `getCurrentNetwork`）的向下兼容
/// - `WifiProbe` 不再把插件与平台通道混用成两个 SSID 来源
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eventChannel = EventChannel('ecjtu_auth/network_events');
  const methodChannel = MethodChannel('ecjtu_auth/network_methods');
  const pluginChannel = MethodChannel('dev.fluttercommunity.plus/network_info');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MockStreamHandlerEventSink? sink;
  var listenCount = 0;
  var cancelCount = 0;
  var pluginCalls = 0;

  setUp(() {
    sink = null;
    listenCount = 0;
    cancelCount = 0;
    pluginCalls = 0;

    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink events) {
          listenCount++;
          sink = events;
        },
        onCancel: (Object? arguments) {
          cancelCount++;
          sink = null;
        },
      ),
    );
    messenger.setMockMethodCallHandler(methodChannel, (MethodCall call) async {
      if (call.method == 'getCurrentNetwork') {
        return <String, Object?>{
          'type': 'wifi',
          'ssid': 'ECJTU-Stu',
          'ssidVisible': true,
        };
      }
      if (call.method == 'getCurrentSsid') {
        return <String, String>{'ssid': 'ECJTU-Stu'};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(pluginChannel, (MethodCall call) async {
      pluginCalls++;
      if (call.method == 'wifiName') return 'PLUGIN-SSID';
      return null;
    });
  });

  tearDown(() {
    messenger.setMockStreamHandler(eventChannel, null);
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockMethodCallHandler(pluginChannel, null);
  });

  group('NetworkType', () {
    test('N1: 原生字符串映射，未知值兜底为 unknown', () {
      expect(NetworkType.parse('wifi'), NetworkType.wifi);
      expect(NetworkType.parse('cellular'), NetworkType.cellular);
      expect(NetworkType.parse('ethernet'), NetworkType.ethernet);
      expect(NetworkType.parse('none'), NetworkType.none);
      // 老原生实现没有该字段；null 不能被当成「无网络」。
      expect(NetworkType.parse(null), NetworkType.unknown);
      expect(NetworkType.parse('LTE'), NetworkType.unknown);
    });

    test('N2: 只有 none 表示没有网络，unknown 不算', () {
      expect(NetworkType.none.isNoNetwork, isTrue);
      expect(NetworkType.unknown.isNoNetwork, isFalse);
      expect(NetworkType.wifi.isWifi, isTrue);
      expect(NetworkType.cellular.isWifi, isFalse);
    });
  });

  group('NlmService 平台守卫', () {
    test('P1: 不受支持的平台既不订阅原生事件也拿不到网络快照', () async {
      final service = NlmService(supportedPlatform: false);
      addTearDown(service.dispose);

      expect(service.isSupported, isFalse);
      service.startListening();
      await pumpEventQueue();

      expect(listenCount, 0, reason: '不支持的平台不应发起 EventChannel listen');
      expect(await service.currentNetwork(), isNull);
      expect(await service.getCurrentSsid(), isNull);
    });

    test('P2: 单测运行在 Linux，默认守卫为 false', () {
      final service = NlmService();
      addTearDown(service.dispose);
      expect(service.isSupported, isFalse);
    });
  });

  group('NlmService 事件', () {
    test('E1: connected/disconnected 带上 type 解码', () async {
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);
      service.startListening();
      await pumpEventQueue();

      final received = <NlmNetworkEvent>[];
      final sub = service.onNetworkChanged.listen(received.add);
      addTearDown(sub.cancel);

      sink!.success(<String, String>{
        'event': 'connected',
        'ssid': 'ECJTU-Stu',
        'type': 'wifi',
      });
      await pumpEventQueue();
      sink!.success(<String, String>{
        'event': 'connected',
        'ssid': '',
        'type': 'cellular',
      });
      await pumpEventQueue();
      sink!.success(<String, String>{'event': 'disconnected', 'type': 'none'});
      await pumpEventQueue();

      expect(received.length, 3);
      expect(received[0].type, NetworkType.wifi);
      expect(received[0].ssid, 'ECJTU-Stu');
      expect(received[1].type, NetworkType.cellular);
      expect(received[1].ssid, '');
      expect(received[2].isDisconnected, isTrue);
      expect(received[2].type, NetworkType.none);
    });

    test('E2: 老原生实现不带 type 时降级为 unknown 而不是崩溃', () async {
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);
      service.startListening();
      await pumpEventQueue();

      final received = <NlmNetworkEvent>[];
      final sub = service.onNetworkChanged.listen(received.add);
      addTearDown(sub.cancel);

      sink!.success(<String, String>{'event': 'connected', 'ssid': 'X'});
      await pumpEventQueue();

      expect(received.single.type, NetworkType.unknown);
      expect(received.single.ssid, 'X');
    });

    test('E3: 重复 startListening 只注册一次原生订阅', () async {
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);

      service.startListening();
      service.startListening();
      service.startListening();
      await pumpEventQueue();

      expect(listenCount, 1);
    });

    test('E4: stopListening 注销原生订阅', () async {
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);

      service.startListening();
      await pumpEventQueue();
      await service.stopListening();
      await pumpEventQueue();

      expect(cancelCount, 1);
      expect(sink, isNull);
    });
  });

  group('NlmService.currentNetwork', () {
    test('C1: 返回类型/SSID/可见性', () async {
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);

      final network = await service.currentNetwork();
      expect(network, isNotNull);
      expect(network!.type, NetworkType.wifi);
      expect(network.ssid, 'ECJTU-Stu');
      expect(network.ssidVisible, isTrue);
    });

    test('C2: WiFi 但读不到名字时 ssidVisible=false，type 仍是 wifi', () async {
      messenger.setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        return <String, Object?>{
          'type': 'wifi',
          'ssid': '',
          'ssidVisible': false,
        };
      });
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);

      final network = await service.currentNetwork();
      expect(network!.type, NetworkType.wifi);
      expect(network.hasSsid, isFalse);
      expect(network.ssidVisible, isFalse);
      expect(await service.getCurrentSsid(), isNull);
    });

    test('C3: 通道不可用（老实现）返回 null，交给调用方兜底', () async {
      messenger.setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        throw MissingPluginException('no impl');
      });
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);

      expect(await service.currentNetwork(), isNull);
    });

    test('C4: 只有 getCurrentSsid 的老实现仍能取到 SSID', () async {
      messenger.setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        if (call.method == 'getCurrentNetwork') {
          throw MissingPluginException('no impl');
        }
        return <String, String>{'ssid': 'ECJTU-Lib'};
      });
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);

      expect(await service.getCurrentSsid(), 'ECJTU-Lib');
    });
  });

  group('WifiProbe 单源', () {
    test('W1: 通道可用且读不到 SSID 时不回退插件（避免双源）', () async {
      messenger.setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        return <String, Object?>{
          'type': 'wifi',
          'ssid': '',
          'ssidVisible': false,
        };
      });
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);
      final probe = WifiProbe(nlmService: service, androidOverride: true);

      expect(await probe.currentSsid(), isNull);
      expect(pluginCalls, 0, reason: '插件若被调用，就会出现第二个 SSID 来源');
    });

    test('W2: 通道不可用时才回退插件', () async {
      messenger.setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        throw MissingPluginException('no impl');
      });
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);
      final probe = WifiProbe(nlmService: service, androidOverride: true);

      expect(await probe.currentSsid(), 'PLUGIN-SSID');
      expect(pluginCalls, greaterThan(0));
    });

    test('W3: 蜂窝网络不返回 SSID', () async {
      messenger.setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        return <String, Object?>{
          'type': 'cellular',
          'ssid': '',
          'ssidVisible': false,
        };
      });
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);
      final probe = WifiProbe(nlmService: service, androidOverride: true);

      expect(await probe.currentSsid(), isNull);
    });
  });
}
