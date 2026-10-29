import 'package:ecjtu_auth/services/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RetryPolicy', () {
    const policy = RetryPolicy(baseDelaySec: 10, maxDelaySec: 300);

    test('指数退避', () {
      expect(policy.delayFor(0), const Duration(seconds: 10));
      expect(policy.delayFor(1), const Duration(seconds: 20));
      expect(policy.delayFor(2), const Duration(seconds: 40));
      expect(policy.delayFor(3), const Duration(seconds: 80));
    });

    test('封顶 maxDelaySec', () {
      expect(policy.delayFor(10), const Duration(seconds: 300));
    });

    test('连续认证失败达到上限', () {
      expect(policy.authFailuresExceeded(2), isFalse);
      expect(policy.authFailuresExceeded(3), isTrue);
    });
  });
}
