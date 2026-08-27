import 'package:flutter_test/flutter_test.dart';

void main() {
  test('指纹对比逻辑验证', () {
    const loginPage = '<html><script>var v46ip="1.2.3.4"</script></html>';
    const loggedInPage = '<html><body>Welcome</body></html>';

    // 模拟首次 check：建立指纹
    String? fingerprint;
    fingerprint ??= loginPage;

    // 模拟指纹对比
    bool isOnline(String currentPage) => currentPage != fingerprint;

    expect(isOnline(loginPage), false); // 同一页面 → 离线
    expect(isOnline(loggedInPage), true); // 不同页面 → 在线
  });

  test('IP 缓存逻辑验证', () {
    String? cachedIp;

    // 模拟提取 IP
    String? extractIp(String html) {
      final match = RegExp(r"v46ip='(.*?)'").firstMatch(html);
      return match?.group(1)?.trim();
    }

    // 模拟 check：缓存 IP
    const portalHtml = "<script>var v46ip='10.16.248.179'</script>";
    cachedIp = extractIp(portalHtml);

    expect(cachedIp, '10.16.248.179');
  });
}
