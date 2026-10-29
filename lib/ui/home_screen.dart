import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      if (mounted) setState(() => _ssid = ssid);
    } catch (_) {}
  }

  /// 在线却拿不到 SSID → 有线连接。启动时探测跑在认证完成前，
  /// 所以显示值要随状态实时推导，不能只在探测时判定一次。
  String? get _displaySsid =>
      (_ssid == null || _ssid!.isEmpty) &&
          widget.service.state == NetState.online
      ? '以太网'
      : _ssid;

  void _onServiceChanged() {
    if (!mounted) return;
    // 网络事件本身带回 SSID，换网后无需再探测一次即可刷新界面。
    final eventSsid = widget.service.lastSsid;
    if (eventSsid != null && eventSsid.isNotEmpty && eventSsid != _ssid) {
      setState(() => _ssid = eventSsid);
      return;
    }
    setState(() {});
  }

  Future<void> _refreshAll() async {
    await widget.service.refreshState();
    await _refreshSsid();
  }

  Future<void> _connect() async {
    final outcome = await widget.service.connectNow();
    if (!mounted) return;
    final hint = outcome.hint;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(hint == null ? outcome.label : '${outcome.label}\n$hint'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: outcome.isGood
            ? Colors.green.shade700
            : Theme.of(context).colorScheme.error,
      ),
    );
    if (outcome == ConnectOutcome.notOnCampus) return;
    await _refreshAll();
  }

  Future<void> _copyLogs() async {
    final text = await widget.service.exportLogs();
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暂无日志'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('日志已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            ssid: _displaySsid,
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
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
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        tooltip: '复制日志',
                        visualDensity: VisualDensity.compact,
                        onPressed: _copyLogs,
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
