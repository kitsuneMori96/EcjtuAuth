import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/net_state.dart';
import '../platform/nlm_service.dart';
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
  CurrentNetwork? _network;
  String? _ssid;
  NetState? _seenState;
  String? _seenSsid;

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
    await _refreshNetwork();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNetwork();
      if (Platform.isAndroid && widget.service.settings.autoConnectOnResume) {
        widget.service.connectNow(source: 'resume');
      }
    }
  }

  /// 网络快照能区分「没有 WiFi」和「有 WiFi 但读不到名字」，SSID 单查做不到。
  Future<void> _refreshNetwork() async {
    final net = await widget.service.probeNetwork();
    if (!mounted) return;
    if (net != null) {
      setState(() => _network = net);
      return;
    }
    final ssid = await widget.service.probeSsid();
    if (!mounted) return;
    setState(() {
      _network = null;
      _ssid = ssid;
    });
  }

  /// 在线却什么都读不到 → 有线连接（Windows 的 WLAN 查询给不出以太网）；
  /// 有 WiFi 但名字不可见 → 权限/ROM 限制，要和「未检测到 WiFi」分开说。
  String? get _displaySsid {
    final net = _network;
    if (net != null) {
      switch (net.type) {
        case NetworkType.wifi:
          return net.hasSsid ? net.ssid : '已连 WiFi，名称不可见';
        case NetworkType.ethernet:
          return '以太网';
        case NetworkType.cellular:
          return null;
        case NetworkType.none:
          return widget.service.state == NetState.online ? '以太网' : null;
        case NetworkType.unknown:
          break;
      }
    }
    if ((_ssid == null || _ssid!.isEmpty) &&
        widget.service.state == NetState.online) {
      return '以太网';
    }
    return _ssid;
  }

  void _onServiceChanged() {
    if (!mounted) return;
    // 网络事件本身带回 SSID，换网后无需再探测一次即可刷新界面。
    final eventSsid = widget.service.lastSsid;
    if (eventSsid != null && eventSsid.isNotEmpty && eventSsid != _ssid) {
      setState(() => _ssid = eventSsid);
    }
    final state = widget.service.state;
    if (state != _seenState || eventSsid != _seenSsid) {
      _seenState = state;
      _seenSsid = eventSsid;
      // 事件只带 SSID，网络类型与名称可见性只有查询接口能给。
      unawaited(_refreshNetwork());
    }
    setState(() {});
  }

  Future<void> _refreshAll() async {
    await widget.service.refreshState();
    await _refreshNetwork();
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
