import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ecjtu_auth/services/log_store.dart';

Future<Directory> tempDir() => Directory.systemTemp.createTemp('ecjtu_log_');

void main() {
  group('LogStore', () {
    late Directory dir;

    setUp(() async {
      dir = await tempDir();
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    LogStore store({
      int maxBytes = 4096,
      int keepFiles = 2,
      int recent = 400,
    }) => LogStore(
      directoryProvider: () async => dir,
      maxBytes: maxBytes,
      keepFiles: keepFiles,
      recentLimit: recent,
    );

    test('L1: 写入后可读回，且按时间正序', () async {
      final s = store();
      s.write('first');
      s.write('second');
      await s.flush();

      expect(s.recentLines(10), ['first', 'second']);
      expect(s.filePath, endsWith('app.log'));

      final text = await File(s.filePath!).readAsString();
      expect(text, 'first\nsecond\n');
    });

    test('L2: 新实例能读回上次的日志', () async {
      final a = store();
      a.write('[00:00:01] 旧日志');
      await a.flush();

      final b = store();
      await b.init();
      expect(b.recentLines(10), ['[00:00:01] 旧日志']);
    });

    test('L3: 超过 maxBytes 时轮转，保留 keepFiles 个历史文件', () async {
      final s = store(maxBytes: 64, keepFiles: 2);
      for (var i = 0; i < 20; i++) {
        s.write('line-$i-xxxxxxxxxxxxxxxx');
      }
      await s.flush();

      final dirPath = File(s.filePath!).parent.path;
      final current = await File(s.filePath!).readAsString();
      expect(current.length, lessThanOrEqualTo(64 + 32));

      final rotated = Directory(dirPath)
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.contains('.log.'))
          .toList();
      expect(rotated, isNotEmpty);
      expect(rotated.length, lessThanOrEqualTo(2));
    });

    test('L4: exportText 包含轮转文件与当前文件', () async {
      final s = store(maxBytes: 80, keepFiles: 2);
      s.write('AAAA-old-line-0000000000');
      await s.flush();
      for (var i = 0; i < 4; i++) {
        s.write('line-$i-xxxxxxxxxxxxxxxx');
      }
      await s.flush();

      final text = await s.exportText();
      expect(text, contains('AAAA-old-line'));
      expect(text, contains('line-3-'));
    });

    test('L5: 初始化失败不抛异常，内存日志仍可用', () async {
      final s = LogStore(
        directoryProvider: () async =>
            throw const FileSystemException('denied'),
        maxBytes: 1024,
      );
      s.write('offline-line');
      await s.flush();

      expect(s.recentLines(5), ['offline-line']);
      expect(await s.exportText(), 'offline-line');
    });

    test('L6: recentLines 只保留最近 limit 行', () async {
      final s = store(recent: 3);
      for (var i = 0; i < 5; i++) {
        s.write('l$i');
      }
      expect(s.recentLines(10), ['l2', 'l3', 'l4']);
      expect(s.recentLines(2), ['l3', 'l4']);
    });
  });
}
