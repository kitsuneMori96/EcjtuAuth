# 更新日志

> 当前处于 **Beta 预发布**阶段，版本号及功能尚在迭代，正式版发布前可能有较多变动。

## v1.1.0-beta - 2026-08-27

### 修复

- **eportal URL 端口编码错误**：`Uri.http(host, ':801/eportal/')` 将 `:801` 编码为路径 `%3A801`，服务器返回 `203 Bad request(1)`。改为 `Uri.http('host:801', '/eportal/')` 正确传递端口
- **假在线误判**：`probeInternet()` 仅检查 HTTP 2xx 状态码，captive portal 劫持后返回 `200+HTML` 被误判为在线。现对 `generate_204` URL 严格要求 204 状态码，普通 URL 校验非空 body 且不含 HTML 标签
- **IP 提取带尾部空格**：`extractIp()` 返回值未 trim，`wlanuserip` 带尾部空格可能导致服务器拒绝
- **认证后探测过快**：POST 登录后立刻探测外网，服务器尚未生效即被 captive portal 拦截。增加 300ms + 500ms 两次探测窗口

### 优化

- **启动即时认证**：新增 `connectNow()` 快速连接方法，跳过状态检测直接登录，启动/回前台时立即尝试认证
- **操作耗时日志**：每步操作（POST 登录、探测验证等）记录毫秒级耗时，便于后续调优
- **超时缩短**：全局 HTTP 超时从 4s 降至 700ms（校园网内网请求通常 <500ms）
- Windows 启动时检测 WiFi 名称，匹配校园网 SSID 即自动连接
- `resumed` 生命周期改为 `connectNow()`，不再先检查 WiFi 状态
- `connectOnce()` 已在线时直接返回，避免焦点变化时无意义重复检测
- `resumed` 仅调 `connectOnce()`，消除并行双重 login POST 竞态

### 移除

- **注销校园网功能**：eportal 注销接口返回 `203 Bad request(2)`，参数格式无文档可考；且该功能与「保持在线」定位无关
- 状态刷新后的白色 SnackBar 通知

### 界面

- WiFi SSID 检测：Android 运行时请求定位权限，修复「未检测到 WiFi」
- 回前台时同步刷新 WiFi 名称
- 登录响应详情日志：显示服务器状态码、请求 URL、账号字段、响应内容

## v1.0.4-beta - 2026-08-26

### 移除

- **注销校园网功能**
- 移除随注销引入的「用户主动注销」标志与相关自动连接拦截逻辑

## v1.0.0~v1.0.3 - 2026-08-26

首个发布版本及迭代修复。基于 [Apauto-to-all/AutoAuthorize](https://github.com/Apauto-to-all/AutoAuthorize) 全面重写，单一 Flutter 代码库覆盖 Windows 与 Android。
