import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecjtu_auth/models/net_state.dart';
import 'package:ecjtu_auth/ui/widgets/status_card.dart';

Future<void> pumpCard(
  WidgetTester tester, {
  required NetState state,
  String? ssid = 'ECJTU-Stu',
  bool busy = false,
  String? detail,
  VoidCallback? onConnect,
  VoidCallback? onRefresh,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatusCard(
          state: state,
          ssid: ssid,
          busy: busy,
          detail: detail,
          onConnect: onConnect,
          onRefresh: onRefresh,
        ),
      ),
    ),
  );
}

void main() {
  group('StatusCard', () {
    testWidgets('S1: 每种状态显示对应文案', (tester) async {
      for (final state in NetState.values) {
        await pumpCard(tester, state: state);
        expect(find.text(state.label), findsOneWidget, reason: '$state');
      }
    });

    testWidgets('S2: 未认证状态给出一键认证按钮并可点击', (tester) async {
      var tapped = 0;
      await pumpCard(
        tester,
        state: NetState.campusBlocked,
        onConnect: () => tapped++,
      );
      await tester.tap(find.text('一键认证'));
      expect(tapped, 1);
    });

    testWidgets('S3: 在线状态显示刷新按钮，不显示认证按钮', (tester) async {
      var refreshed = 0;
      await pumpCard(
        tester,
        state: NetState.online,
        onRefresh: () => refreshed++,
      );
      expect(find.text('一键认证'), findsNothing);
      await tester.tap(find.text('刷新状态'));
      expect(refreshed, 1);
    });

    testWidgets('S4: 失败原因会显示在卡片上', (tester) async {
      await pumpCard(tester, state: NetState.unknown, detail: '超时：连接超时（3s）');
      expect(find.text('超时：连接超时（3s）'), findsOneWidget);
    });

    testWidgets('S5: 忙碌时显示进度且隐藏按钮', (tester) async {
      await pumpCard(tester, state: NetState.checking, busy: true);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('刷新状态'), findsNothing);
      expect(find.text('一键认证'), findsNothing);
    });

    testWidgets('S6: 无 SSID 时显示占位文案', (tester) async {
      await pumpCard(tester, state: NetState.noCampusWifi, ssid: null);
      expect(find.text('未检测到 WiFi'), findsOneWidget);
    });
  });
}
