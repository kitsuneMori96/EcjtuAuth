import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/net_state.dart';
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
  String? _ssid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service.addListener(_onServiceChanged);
    _requestPermissionAndInit();
  }

  Future<void> _requestPermissionAndInit() async {
    if (Platform.isAndroid) {
      await Permission.location.request();
    }
    await _refreshSsid();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSsid();
      if (Platform.isAndroid && widget.service.settings.autoConnectOnResume) {
        widget.service.connectNow();
      }
    }
  }

  Future<void> _refreshSsid() async {
    try {
      final ssid = await widget.service.probeSsid();
      if (mounted) {
        // 在线但无 SSID → 有线连接
        if (ssid == null && widget.service.state == NetState.online) {
          setState(() => _ssid = '以太网');
        } else {
          setState(() => _ssid = ssid);
        }
      }
    } catch (_) {}
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshAll() async {
    await widget.service.refreshState();
    await _refreshSsid();
  }

  Future<void> _connect() async {
    final outcome = await widget.service.connectNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.label),
        behavior: SnackBarBehavior.floating,
        backgroundColor: outcome.isGood
            ? Colors.green.shade700
            : Theme.of(context).colorScheme.error,
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
            detail: service.statusDetail,
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
                      Icon(
                        Icons.terminal_rounded,
                        size: 17,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '运行日志',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
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
