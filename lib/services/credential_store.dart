import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/campus_account.dart';
import '../models/operator.dart';

/// 基于 flutter_secure_storage 的凭据存储。
/// Android 走 Keystore，Windows 走 DPAPI，均加密落盘，
/// 替代原项目的明文 JSON 文件。
class CredentialStore {
  CredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kUsername = 'username';
  static const _kPassword = 'password';
  static const _kOperator = 'operator';

  Future<CampusAccount?> read() async {
    final username = await _storage.read(key: _kUsername);
    final password = await _storage.read(key: _kPassword);
    final operator = await _storage.read(key: _kOperator);
    if (username == null || password == null) return null;
    if (username.isEmpty || password.isEmpty) return null;
    return CampusAccount(
      username: username,
      password: password,
      operator: Operator.fromSuffix(operator ?? ''),
    );
  }

  Future<void> save(CampusAccount account) async {
    await _storage.write(key: _kUsername, value: account.username);
    await _storage.write(key: _kPassword, value: account.password);
    await _storage.write(key: _kOperator, value: account.operator.suffix);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kUsername);
    await _storage.delete(key: _kPassword);
    await _storage.delete(key: _kOperator);
  }
}
