import 'package:ecjtu_auth/services/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsStore', () {
    test('保存/读取往返保持类型与字段', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SettingsStore(prefs);
      const settings = AppSettings(
        portalHost: '10.0.0.1',
        ssidCampus: 'Campus-A',
        ssidFree: 'Free-B',
        autoRetry: false,
        baseRetryDelaySec: 5,
        maxRetryDelaySec: 60,
        launchAtStartup: true,
        autoConnectOnResume: false,
        offlinePageLength: 1234,
      );

      await store.save(settings);
      final loaded = await store.load();

      expect(loaded.toMap(), settings.toMap());
      expect(loaded.offlinePageLength, 1234);
    });

    test('兼容 1.x 的 query-string 旧格式', () async {
      SharedPreferences.setMockInitialValues({
        'settings.':
            'portalHost=192.168.1.1&autoRetry=0&launchAtStartup=1'
            '&autoConnectOnResume=0&offlinePageLength=3661',
      });
      final prefs = await SharedPreferences.getInstance();
      final loaded = await SettingsStore(prefs).load();

      expect(loaded.portalHost, '192.168.1.1');
      expect(loaded.autoRetry, isFalse);
      expect(loaded.launchAtStartup, isTrue);
      expect(loaded.autoConnectOnResume, isFalse);
      expect(loaded.offlinePageLength, 3661);
      expect(loaded.ssidCampus, 'ECJTU-Stu');
    });

    test('损坏的 JSON 回退到默认值', () async {
      SharedPreferences.setMockInitialValues({'settings.v2': '{not-json'});
      final prefs = await SharedPreferences.getInstance();
      final loaded = await SettingsStore(prefs).load();

      expect(loaded.portalHost, '172.16.2.100');
      expect(loaded.offlinePageLength, isNull);
    });
  });
}
