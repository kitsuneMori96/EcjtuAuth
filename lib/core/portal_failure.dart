/// portal / 认证接口的失败类型，用于把「网络问题」和「凭据问题」区分开。
enum PortalFailure {
  timeout,
  refused,
  unreachable,
  httpStatus,
  badContent,
  unknown,
}

extension PortalFailureX on PortalFailure {
  String get label => switch (this) {
    PortalFailure.timeout => '请求超时',
    PortalFailure.refused => '连接被拒绝',
    PortalFailure.unreachable => '网络不可达',
    PortalFailure.httpStatus => '服务器返回异常状态',
    PortalFailure.badContent => '响应内容异常',
    PortalFailure.unknown => '未知错误',
  };

  /// 给用户的可操作建议，直接显示在状态卡片上，不必去翻 snackbar。
  String get hint => switch (this) {
    PortalFailure.timeout => '先关闭代理或 VPN 再试；校园网维护期间也会超时',
    PortalFailure.refused => '门户拒绝连接：检查设置里的门户地址，或确认已连校园网',
    PortalFailure.unreachable => '无法到达门户：确认已连校园网，并关闭代理或 VPN',
    PortalFailure.httpStatus => '服务器返回异常状态，稍后重试',
    PortalFailure.badContent => '响应内容异常，可能被门户劫持，稍后重试',
    PortalFailure.unknown => '请复制日志提交 Issue 以便排查',
  };
}

class PortalException implements Exception {
  const PortalException(this.failure, this.message, {this.statusCode});

  final PortalFailure failure;
  final String message;
  final int? statusCode;

  @override
  String toString() => '${failure.label}: $message';
}
