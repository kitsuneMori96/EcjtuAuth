import 'package:http/http.dart' as http;

/// portal 离线页面长度仓库：Gitee 优先，GitHub 兜底。
///
/// 两个源存放同一份 `portal_length.txt`（正整数）。
/// Gitee 面向国内网络，GitHub 作为镜像兜底。
/// 主仓库 `portal_length.txt` 更新后由 CI 自动同步到 Gitee。
class PortalLengthRepository {
  PortalLengthRepository._();

  /// Gitee 镜像（国内优先）。
  static const giteeUrl =
      'https://gitee.com/kitsuneMori/EcjtuAuth-portal/raw/master/portal_length.txt';

  /// GitHub 源（兜底）。
  static const githubUrl =
      'https://raw.githubusercontent.com/kitsuneMori96/EcjtuAuth/main/portal_length.txt';

  /// 按优先级依次尝试各数据源。
  ///
  /// 返回 `(长度, 源标识)`；全部源失败返回 null。
  /// [client] 仅供测试注入，默认使用独立 [http.Client]。
  static Future<(int, String)?> fetch({
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final c = client ?? http.Client();
    final owned = client == null;
    try {
      const sources = <String, String>{
        'Gitee': giteeUrl,
        'GitHub': githubUrl,
      };
      for (final entry in sources.entries) {
        try {
          final res = await c.get(Uri.parse(entry.value)).timeout(timeout);
          if (res.statusCode != 200) continue;
          final length = int.tryParse(res.body.trim());
          if (length == null || length <= 0) continue;
          return (length, entry.key);
        } catch (_) {
          // 尝试下一个源
        }
      }
      return null;
    } finally {
      if (owned) c.close();
    }
  }
}
