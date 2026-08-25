import 'operator.dart';

/// 用户在校园网的账户信息。
class CampusAccount {
  const CampusAccount({
    required this.username,
    required this.password,
    this.operator = Operator.campus,
  });

  final String username;
  final String password;
  final Operator operator;

  bool get isValid => username.isNotEmpty && password.isNotEmpty;

  CampusAccount copyWith({
    String? username,
    String? password,
    Operator? operator,
  }) {
    return CampusAccount(
      username: username ?? this.username,
      password: password ?? this.password,
      operator: operator ?? this.operator,
    );
  }
}
