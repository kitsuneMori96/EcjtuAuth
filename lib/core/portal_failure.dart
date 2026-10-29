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
}

class PortalException implements Exception {
  const PortalException(this.failure, this.message, {this.statusCode});

  final PortalFailure failure;
  final String message;
  final int? statusCode;

  @override
  String toString() => '${failure.label}: $message';
}
