import 'package:flutter/material.dart';

import '../../models/net_state.dart';

/// 主页顶部的大状态卡片：颜色与图标随 NetState 变化。
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.state,
    required this.ssid,
    required this.busy,
    this.onConnect,
    this.onRefresh,
  });

  final NetState state;
  final String? ssid;
  final bool busy;
  final VoidCallback? onConnect;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, actionLabel) = switch (state) {
      NetState.online => (
          Icons.verified_user_rounded,
          Colors.green.shade600,
          null,
        ),
      NetState.campusBlocked => (
          Icons.wifi_password_rounded,
          scheme.error,
          '一键认证',
        ),
      NetState.noCampusWifi => (
          Icons.wifi_off_rounded,
          scheme.outline,
          null
        ),
      NetState.checking => (
          Icons.sync_rounded,
          scheme.primary,
          null
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: color,
                      ),
                    )
                  : Icon(icon, size: 52, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              state.label,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_tethering_rounded,
                    size: 15, color: scheme.outline),
                const SizedBox(width: 4),
                Text(
                  (ssid == null || ssid!.isEmpty) ? '未检测到 WiFi' : ssid!,
                  style: TextStyle(color: scheme.outline, fontSize: 13),
                ),
              ],
            ),
            if (!busy) ...[
              const SizedBox(height: 20),
              if (actionLabel != null)
                FilledButton.icon(
                  onPressed: onConnect,
                  icon: const Icon(Icons.bolt_rounded),
                  label: Text(actionLabel),
                )
              else
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新状态'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
