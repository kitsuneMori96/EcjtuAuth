import 'dart:math';

/// 自动重试的退避策略（纯函数，便于单测）。
class RetryPolicy {
  const RetryPolicy({
    required this.baseDelaySec,
    required this.maxDelaySec,
    this.maxAuthFailures = 3,
    this.maxTransportRetries = 5,
  });

  final int baseDelaySec;
  final int maxDelaySec;

  /// 连续认证失败达到该次数后停止重试，避免密码错误时反复登录。
  final int maxAuthFailures;

  /// 连续「portal 不可达」达到该次数后停止重试（约 10s→160s）。
  final int maxTransportRetries;

  Duration delayFor(int attempt) {
    final exponent = min(attempt, 6);
    final seconds = min(maxDelaySec, baseDelaySec * (1 << exponent));
    return Duration(seconds: seconds);
  }

  bool authFailuresExceeded(int consecutive) => consecutive >= maxAuthFailures;
}
