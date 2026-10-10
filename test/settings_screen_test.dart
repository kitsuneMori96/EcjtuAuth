import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecjtu_auth/core/eportal_client.dart';
import 'package:ecjtu_auth/core/network_checker.dart';
import 'package:ecjtu_auth/services/auto_connect.dart';
import 'package:ecjtu_auth/services/credential_store.dart';
import 'package:ecjtu_auth/services/settings_store.dart';
import 'package:ecjtu_auth/ui/settings_screen.dart';

Future<AutoConnectService> makeService() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return AutoConnectService(
    eportal: EportalClient(),
    checker: NetworkChecker(),
    credentials: CredentialStore(),
    settings: SettingsStore(prefs),
  );
}

Future<void> tapFetchButton(WidgetTester tester) async {
  final button = find.text('从仓库获取最新长度');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}
Future<void> pumpSettings(
  WidgetTester tester,
  AutoConnectService service, {
  Future<(int, String)?> Function()? fetchLength,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SettingsScreen(service: service, fetchLength: fetchLength),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsScreen 在线检测校准', () {
    testWidgets('W1: 拉取成功显示长度与来源', (tester) async {
      final service = await makeService();
      await pumpSettings(tester, service,
          fetchLength: () async => (3661, 'Gitee'));

      await tapFetchButton(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('3661 chars (via Gitee)'), findsOneWidget);
      expect(find.textContaining('当前长度: 3661'), findsOneWidget);
      expect((await service.settingsStore.load()).offlinePageLength, 3661);
    });

    testWidgets('W2: 全部源失败显示错误提示', (tester) async {
      final service = await makeService();
      await pumpSettings(tester, service, fetchLength: () async => null);

      await tapFetchButton(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('均不可用'), findsOneWidget);
    });

    testWidgets('W3: 请求期间按钮禁用并显示进度', (tester) async {
      final service = await makeService();
      await pumpSettings(
        tester,
        service,
        fetchLength: () async {
          await Future.delayed(const Duration(milliseconds: 300));
          return (3661, 'GitHub');
        },
      );

      await tapFetchButton(tester);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      await tester.pumpAndSettle();
      expect(find.text('从仓库获取最新长度'), findsOneWidget);
      expect(find.textContaining('via GitHub'), findsOneWidget);
    });
  });
}
