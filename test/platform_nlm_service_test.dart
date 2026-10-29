import 'package:ecjtu_auth/platform/nlm_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 覆盖平台守卫与事件解码：Android 接入后 `NlmService` 不再只对 Windows 生效，
/// 这两条都属于「静默失效、没有编译错误」的风险点，必须由测试锁住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eventChannel = EventChannel('ecjtu_auth/network_events');
  const methodChannel = MethodChannel('ecjtu_auth/network_methods');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MockStreamHandlerEventSink? sink;
  var listenCount = 0;
  var cancelCount = 0;

  setUp(() {
    sink = null;
    listenCount = 0;
    cancelCount = 0;

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
      if (call.method == 'getCurrentSsid') {
        return <String, String>{'ssid': 'ECJTU-Stu'};
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockStreamHandler(eventChannel, null);
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  group('NlmService 平台守卫', () {
    test('P1: 不受支持的平台既不订阅原生事件也拿不到 SSID', () async {
      final service = NlmService(supportedPlatform: false);
      addTearDown(service.dispose);

      expect(service.isSupported, isFalse);
      service.startListening();
      await pumpEventQueue();

      expect(listenCount, 0, reason: '不支持的平台不应发起 EventChannel listen');
      expect(await service.getCurrentSsid(), isNull);
    });

    test('P2: Windows/Android 之外的真实平台默认不启用', () {
      // 单测运行在 Linux，默认守卫应为 false，证明未把守卫写成「恒真」。
      final service = NlmService();
      addTearDown(service.dispose);
      expect(service.isSupported, isFalse);
    });
  });

  group('NlmService 事件', () {
    test('P3: connected/disconnected 解码为 NlmNetworkEvent', () async {
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);
      service.startListening();
      await pumpEventQueue();

      expect(listenCount, 1);

      final received = <NlmNetworkEvent>[];
      final sub = service.onNetworkChanged.listen(received.add);
      addTearDown(sub.cancel);

      sink!.success(<String, String>{'event': 'connected', 'ssid': 'ECJTU-Stu'});
      await pumpEventQueue();
      sink!.success(<String, String>{'event': 'disconnected'});
      await pumpEventQueue();

      expect(received.length, 2);
      expect(received[0].isConnected, isTrue);
      expect(received[0].ssid, 'ECJTU-Stu');
      expect(received[1].isDisconnected, isTrue);
      expect(received[1].ssid, '', reason: '载荷缺 ssid 时应归一为空串');
    });

    test('P4: 重复 startListening 只注册一次原生订阅', () async {
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);

      service.startListening();
      service.startListening();
      service.startListening();
      await pumpEventQueue();

      // Android 每次 registerDefaultNetworkCallback 都会新增一个回调，
      // 重复订阅会成倍放大事件与耗电。
      expect(listenCount, 1);
    });

    test('P5: stopListening 注销原生订阅', () async {
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);

      service.startListening();
      await pumpEventQueue();
      expect(listenCount, 1);

      await service.stopListening();
      await pumpEventQueue();

      expect(cancelCount, 1);
      expect(sink, isNull);
    });
  });

  group('NlmService.getCurrentSsid', () {
    test('P6: 正常返回 SSID', () async {
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);

      expect(await service.getCurrentSsid(), 'ECJTU-Stu');
    });

    test('P7: 空串与异常统一归一为 null', () async {
      final service = NlmService(supportedPlatform: true);
      addTearDown(service.dispose);

      messenger.setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        return <String, String>{'ssid': ''};
      });
      expect(await service.getCurrentSsid(), isNull);

      messenger.setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        throw PlatformException(code: 'unavailable');
      });
      expect(await service.getCurrentSsid(), isNull);
    });
  });
}
