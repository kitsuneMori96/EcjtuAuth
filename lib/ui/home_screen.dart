import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/net_state.dart';
import '../platform/wifi_probe.dart';
import '../services/auto_connect.dart';
import 'widgets/log_view.dart';
import 'widgets/status_card.dart';

/// 主页：状态卡片 + 操作按钮 + 运行日志。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.service});

  final AutoConnectService service;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static final WifiProbe _wifiProbe = WifiProbe();

  String? _ssid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service.addListener(_onServiceChanged);
    AutoConnectService.currentSsid = () => _wifiProbe.currentSsid();
    _requestPermissionAndInit();
  }

  Future<void> _requestPermissionAndInit() async {
    // Android 需要运行时请求定位权限才能获取 WiFi SSID
    if (Platform.isAndroid) {
      final status = await Permission.location.request();
      if (!status.isGranted && !status.isLimited) {
        // 权限被拒绝，仍然继续，只是 SSID 检测不可用
      }
    }
    _refreshAll();
    // 启动时自动尝试认证（如已在线则跳过）
    widget.service.connectOnce();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回到前台时刷新 WiFi 名称
      _refreshSsid();
      if (widget.service.settings.autoConnectOnResume) {
        widget.service.connectOnce();
      }
    }
  }

  Future<void> _refreshSsid() async {
    try {
      final ssid = await _wifiProbe.currentSsid();
      if (mounted) setState(() => _ssid = _cleanSsid(ssid));
    } catch (_) {}
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshAll() async {
    await widget.service.refreshState();
    await _refreshSsid();
  }

  String? _cleanSsid(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1);
    }
    return s.isEmpty ? null : s;
  }

  Future<void> _connect() async {
    final outcome = await widget.service.connectOnce();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.label),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            outcome.isGood ? Colors.green.shade700 : Theme.of(context).colorScheme.error,
      ),
    );
    if (outcome == ConnectOutcome.notOnCampus) return;
    await _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.service.removeListener(_onServiceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          StatusCard(
            state: service.busy ? NetState.checking : service.state,
            ssid: _ssid,
            busy: service.busy,
            onConnect: _connect,
            onRefresh: _refreshAll,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    children: [
                      Icon(Icons.terminal_rounded,
                          size: 17, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 6),
                      Text('运行日志', style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                ),
                LogView(lines: service.logLines.take(30).toList()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
