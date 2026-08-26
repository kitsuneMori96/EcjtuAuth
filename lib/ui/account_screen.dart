import 'package:flutter/material.dart';

import '../models/campus_account.dart';
import '../models/operator.dart';
import '../services/credential_store.dart';

/// 账户配置页：学号 / 密码 / 运营商，保存到加密存储。
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.credentialStore});

  final CredentialStore credentialStore;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  Operator _operator = Operator.campus;
  bool _obscure = true;
  bool _loading = true;

  static const operatorLabels = {
    Operator.campus: '校园网账号（无后缀）',
    Operator.cmcc: '中国移动 (@cmcc)',
    Operator.telecom: '中国电信 (@telecom)',
    Operator.unicom: '中国联通 (@unicom)',
  };

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final account = await widget.credentialStore.read();
    if (!mounted) return;
    if (account != null) {
      setState(() {
        _usernameCtrl.text = account.username;
        _passwordCtrl.text = account.password;
        _operator = account.operator;
      });
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.credentialStore.save(
      CampusAccount(
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        operator: _operator,
      ),
    );
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('账号信息已加密保存'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除账号'),
        content: const Text('将删除已保存的学号与密码，确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.credentialStore.clear();
    if (!mounted) return;
    setState(() {
      _usernameCtrl.clear();
      _passwordCtrl.clear();
      _operator = Operator.campus;
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: '学号',
                prefixIcon: Icon(Icons.person_rounded),
                hintText: '例如 202300010101',
              ),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请输入学号' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? '请输入密码' : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<Operator>(
              initialValue: _operator,
              decoration: const InputDecoration(
                labelText: '运营商',
                prefixIcon: Icon(Icons.sim_card_rounded),
              ),
              items: [
                for (final op in Operator.values)
                  DropdownMenuItem(value: op, child: Text(operatorLabels[op]!)),
              ],
              onChanged: (v) => setState(() => _operator = v ?? Operator.campus),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('保存'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('清除已保存的账号'),
            ),
          ],
        ),
      ),
    );
  }
}
