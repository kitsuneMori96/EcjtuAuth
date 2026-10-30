import 'package:flutter_test/flutter_test.dart';
import 'package:ecjtu_auth/models/net_state.dart';

void main() {
  group('ConnectOutcome 提示', () {
    test('成功的两种结果没有额外建议', () {
      expect(ConnectOutcome.success.hint, isNull);
      expect(ConnectOutcome.alreadyOnline.hint, isNull);
    });

    test('每种失败都给可操作建议', () {
      const failures = [
        ConnectOutcome.authFailed,
        ConnectOutcome.noAccount,
        ConnectOutcome.notOnCampus,
        ConnectOutcome.portalUnreachable,
        ConnectOutcome.unverified,
        ConnectOutcome.failed,
      ];
      for (final f in failures) {
        expect(f.hint, isNotNull, reason: '$f 缺少建议');
        expect(f.hint, isNotEmpty, reason: '$f 建议为空');
      }
    });

    test('unverified 提示指向校准入口', () {
      expect(ConnectOutcome.unverified.hint, contains('设置页'));
    });
  });
}
