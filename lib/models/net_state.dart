/// 设备当前的网络状态。
enum NetState {
  /// 未连接校园网 SSID，或认证服务器不可达。
  noCampusWifi,

  /// 已连接校园网但尚未通过认证（无外网）。
  campusBlocked,

  /// 已认证，外网可用。
  online,

  /// 正在检测中。
  checking,

  /// portal 不可达或未校准，无法判断。
  unknown,
}

extension NetStateX on NetState {
  String get label => switch (this) {
    NetState.noCampusWifi => '未连接校园网',
    NetState.campusBlocked => '校园网待认证',
    NetState.online => '已在线',
    NetState.checking => '检测中…',
    NetState.unknown => '无法判断',
  };
}

/// 一次完整「连接」动作的结果。
enum ConnectOutcome {
  /// 无需操作，本来就在线。
  alreadyOnline,

  /// 认证成功并复验通过。
  success,

  /// 学号/密码/运营商错误或服务器拒绝。
  authFailed,

  /// 当前不在校园网环境。
  notOnCampus,

  /// portal 或登录接口不可达（超时/拒绝/网络错误）。
  portalUnreachable,

  /// 已提交认证，但缺少基准长度，无法验证结果。
  unverified,

  /// 内部异常（存储、未预期错误等）。
  failed,
}

extension ConnectOutcomeX on ConnectOutcome {
  bool get isGood =>
      this == ConnectOutcome.success || this == ConnectOutcome.alreadyOnline;

  String get label => switch (this) {
    ConnectOutcome.alreadyOnline => '本就在线，无需认证',
    ConnectOutcome.success => '认证成功',
    ConnectOutcome.authFailed => '认证失败，请检查账号信息',
    ConnectOutcome.notOnCampus => '未连接校园网 WiFi',
    ConnectOutcome.portalUnreachable => '认证服务器不可达',
    ConnectOutcome.unverified => '已提交认证，但无法验证结果（未校准长度）',
    ConnectOutcome.failed => '连接失败（内部错误）',
  };
}
