import 'package:flutter/material.dart';

/// 运行日志视图。
class LogView extends StatelessWidget {
  const LogView({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '暂无日志',
          style: TextStyle(color: scheme.outline, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: lines.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          lines[i],
          style: TextStyle(
            fontSize: 12.5,
            fontFamily: 'monospace',
            color: i == 0 ? scheme.onSurface : scheme.outline,
          ),
        ),
      ),
    );
  }
}
