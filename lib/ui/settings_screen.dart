import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../platform/desktop_service.dart';
import '../services/auto_connect.dart';
import '../services/settings_store.dart';

/// 设置页：认证服务器 / SSID / 自动重连 / 开机自启。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.service});

  final AutoConnectService service;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _ssidCampusCtrl;
  late final TextEditingController _ssidFreeCtrl;

  AppSettings _settings = const AppSettings();
  bool _startupEnabled = false;
  bool _loading = true;
  bool _fetchingLength = false;

  /// 仓库中最新的离线页面长度。
  static const _repoLengthUrl =
      'https://raw.githubusercontent.com/kitsuneMori96/AuinEcjtuWifi/main/portal_length.txt';

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController();
    _ssidCampusCtrl = TextEditingController();
    _ssidFreeCtrl = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.service.settingsStore.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _hostCtrl.text = s.portalHost;
      _ssidCampusCtrl.text = s.ssidCampus;
      _ssidFreeCtrl.text = s.ssidFree;
      _loading = false;
    });
    if (Platform.isWindows) {
      final enabled = await DesktopService.launchAtStartupIsEnabled();
      if (mounted) setState(() => _startupEnabled = enabled);
    }
  }

  Future<void> _save() async {
    await widget.service.saveSettings(
      _settings.copyWith(
        portalHost: _hostCtrl.text.trim(),
        ssidCampus: _ssidCampusCtrl.text.trim(),
        ssidFree: _ssidFreeCtrl.text.trim(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _fetchLengthFromRepo() async {
    setState(() => _fetchingLength = true);
    try {
      final res = await http.get(Uri.parse(_repoLengthUrl))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final length = int.tryParse(res.body.trim());
      if (length == null || length <= 0) {
        throw Exception('内容格式错误: ${res.body.trim()}');
      }
      setState(() {
        _settings = _settings.copyWith(offlinePageLength: length);
      });
      await widget.service.saveSettings(_settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已获取最新长度: $length chars'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('获取失败: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _fetchingLength = false);
    }
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _ssidCampusCtrl.dispose();
    _ssidFreeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionTitle(context, '网络参数'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextFormField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(
                    labelText: '认证服务器地址',
                    hintText: '172.16.2.100',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ssidCampusCtrl,
                  decoration:
                      const InputDecoration(labelText: '校园网 SSID（计费网络）'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ssidFreeCtrl,
                  decoration:
                      const InputDecoration(labelText: '免费网络 SSID（图书馆）'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _sectionTitle(context, '自动化'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('自动重试认证'),
                subtitle: const Text('失败后按指数退避间隔自动重试'),
                value: _settings.autoRetry,
                onChanged: (v) =>
                    setState(() => _settings = _settings.copyWith(autoRetry: v)),
              ),
              SwitchListTile(
                title: const Text('回到前台时自动连接'),
                subtitle: const Text('Android：切回应用即尝试认证'),
                value: _settings.autoConnectOnResume,
                onChanged: (v) => setState(
                    () => _settings = _settings.copyWith(autoConnectOnResume: v)),
              ),
              if (Platform.isWindows)
                SwitchListTile(
                  title: const Text('开机自启'),
                  subtitle: const Text('随系统启动并最小化到托盘'),
                  value: _startupEnabled,
                  onChanged: (v) async {
                    await DesktopService.configureLaunchAtStartup(v);
                    if (mounted) setState(() => _startupEnabled = v);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _sectionTitle(context, '在线检测校准'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '离线页面长度',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '用于判断是否已认证。如果认证状态判断有误，可能是长度已变化，点击下方按钮获取最新长度。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _settings.offlinePageLength != null
                      ? '当前长度: ${_settings.offlinePageLength} chars'
                      : '未获取 — 请先点击下方按钮',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _settings.offlinePageLength != null
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _fetchingLength ? null : _fetchLengthFromRepo,
                  child: _fetchingLength
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('从仓库获取最新长度'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_rounded),
          label: const Text('保存设置'),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
