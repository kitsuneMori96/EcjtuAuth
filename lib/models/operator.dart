/// 校园网认证可选运营商及其 eportal 账号后缀。
enum Operator {
  campus('', '校园网账号'),
  cmcc('@cmcc', '中国移动'),
  telecom('@telecom', '中国电信'),
  unicom('@unicom', '中国联通');

  const Operator(this.suffix, this.label);

  /// 拼接在学号后的运营商后缀，如 `20230001@cmcc`。
  final String suffix;
  final String label;

  static Operator fromLabel(String label) {
    for (final op in Operator.values) {
      if (op.label == label) return op;
    }
    return Operator.campus;
  }

  static Operator fromSuffix(String suffix) {
    for (final op in Operator.values) {
      if (op.suffix == suffix) return op;
    }
    return Operator.campus;
  }
}

extension OperatorX on Operator {
  String get storageValue => name;
}
