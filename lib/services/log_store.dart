import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 运行日志落盘：追加写入、按大小轮转、启动时读回最近若干行。
///
/// 内存里的日志只在进程存活期有效，崩溃或退出后无法回溯，
/// 因此把同样的行追加到 `<应用支持目录>/logs/app.log`，
/// 超过 [maxBytes] 时把当前文件轮转为 `.1`、`.2`… 供导出。
class LogStore {
  LogStore({
    Future<Directory> Function()? directoryProvider,
    this.maxBytes = 512 * 1024,
    this.keepFiles = 2,
    this.recentLimit = 400,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const _dirName = 'logs';
  static const _fileName = 'app.log';

  final Future<Directory> Function() _directoryProvider;
  final int maxBytes;
  final int keepFiles;
  final int recentLimit;

  File? _file;
  Future<void>? _initFuture;
  bool _initialized = false;
  final List<String> _pending = [];
  Future<void>? _flushFuture;
  int _size = 0;
  final List<String> _recent = [];

  /// 日志文件路径；初始化失败或未初始化时为 null。
  String? get filePath => _file?.path;

  Future<void> init() => _initFuture ??= _open();

  Future<void> _open() async {
    try {
      final base = await _directoryProvider();
      final dir = Directory('${base.path}${Platform.pathSeparator}$_dirName');
      await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      if (await file.exists()) {
        _size = await file.length();
        _recent
          ..clear()
          ..addAll(await _tailLines(file, recentLimit));
      }
      _file = file;
      _initialized = true;
      await _rotateIfNeeded();
    } catch (e) {
      debugPrint('日志初始化失败: $e');
    }
  }

  /// 追加一行日志。初始化未完成或失败时只保留在内存中，不阻塞调用方。
  void write(String line) {
    _recent.add(line);
    if (_recent.length > recentLimit) {
      _recent.removeRange(0, _recent.length - recentLimit);
    }
    _pending.add(line);
    _flushFuture ??= _drain();
  }

  /// 等待当前缓冲全部落盘（测试与退出前使用）。
  Future<void> flush() async {
    while (_flushFuture != null) {
      await _flushFuture;
    }
  }

  /// 启动时读回的最近日志，按时间正序（最旧在前）。
  List<String> recentLines(int limit) {
    if (limit >= _recent.length) return List.of(_recent);
    return _recent.sublist(_recent.length - limit);
  }

  /// 读取当前日志与轮转文件，供「复制日志」使用。
  Future<String> exportText() async {
    await init();
    final file = _file;
    if (file == null) return recentLines(recentLimit).join('\n');
    final parts = <String>[];
    for (var i = keepFiles; i >= 1; i--) {
      final rotated = File('${file.path}.$i');
      if (await rotated.exists()) parts.add(await _readCapped(rotated));
    }
    if (await file.exists()) parts.add(await _readCapped(file));
    return parts.where((p) => p.isNotEmpty).join('\n');
  }

  Future<void> _drain() async {
    try {
      await init();
      if (!_initialized) {
        _pending.clear();
        return;
      }
      while (_pending.isNotEmpty) {
        // 按体积分批，避免一次性写入远超 maxBytes 的内容让轮转失效。
        final batch = <String>[];
        var bytes = 0;
        while (_pending.isNotEmpty && bytes + _pending.first.length < maxBytes) {
          final line = _pending.removeAt(0);
          batch.add(line);
          bytes += line.length + 1;
        }
        if (batch.isEmpty) batch.add(_pending.removeAt(0));
        final chunk = '${batch.join('\n')}\n';
        final size = chunk.length;
        if (_size + size > maxBytes) await _rotate();
        await _file!.writeAsString(chunk, mode: FileMode.append);
        _size += size;
      }
    } catch (e) {
      debugPrint('日志写入失败: $e');
    } finally {
      _flushFuture = null;
    }
  }

  Future<void> _rotateIfNeeded() async {
    if (_size > maxBytes) await _rotate();
  }

  Future<void> _rotate() async {
    final file = _file;
    if (file == null) return;
    try {
      for (var i = keepFiles; i >= 1; i--) {
        final target = File('${file.path}.$i');
        final source = i == 1 ? file : File('${file.path}.${i - 1}');
        if (!await source.exists()) continue;
        if (await target.exists()) await target.delete();
        await source.rename(target.path);
      }
      _size = 0;
    } catch (e) {
      debugPrint('日志轮转失败: $e');
      _size = 0;
    }
  }

  Future<String> _readCapped(File file) async {
    final text = await file.readAsString();
    if (text.length <= maxBytes) return text;
    return text.substring(text.length - maxBytes);
  }

  Future<List<String>> _tailLines(File file, int limit) async {
    try {
      final text = await _readCapped(file);
      final lines = text.split('\n').where((l) => l.isNotEmpty).toList();
      if (lines.length <= limit) return lines;
      return lines.sublist(lines.length - limit);
    } catch (_) {
      return const [];
    }
  }
}
