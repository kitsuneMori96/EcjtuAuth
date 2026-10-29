import 'package:flutter_test/flutter_test.dart';
import 'package:ecjtu_auth/platform/nlm_service.dart';

void main() {
  group('NlmNetworkEvent', () {
    test('N1: 事件类型判断', () {
      const cases = {
        'connected': [true, false, false, false],
        'disconnected': [false, true, false, false],
        'wake': [false, false, true, false],
        'suspend': [false, false, false, true],
        'unknown': [false, false, false, false],
      };
      cases.forEach((event, expected) {
        final e = NlmNetworkEvent(event: event, ssid: 'ECJTU-Stu');
        expect(
          [e.isConnected, e.isDisconnected, e.isWake, e.isSuspend],
          expected,
          reason: event,
        );
      });
    });

    test('N2: SSID 原样保留，toString 含两者', () {
      const e = NlmNetworkEvent(event: 'connected', ssid: 'EcjtuLib_Free');
      expect(e.ssid, 'EcjtuLib_Free');
      expect(e.toString(), contains('connected'));
      expect(e.toString(), contains('EcjtuLib_Free'));
    });
  });
}
