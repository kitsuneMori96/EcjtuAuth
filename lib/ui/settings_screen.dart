import 'dart:io';

import 'package:flutter/material.dart';

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
