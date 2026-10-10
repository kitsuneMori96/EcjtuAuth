# 更新日志

## 1.1.1 - 2026-10-10

### 修复

- **休眠唤醒重连失效**：唤醒时立即重置状态为「检测中」，确保 2 秒后的重连回调能执行
- **唤醒后无重试**：认证失败自动重试最多 3 次，每次间隔 5 秒
- **新用户认证成功后无法自证在线**：`offlinePageLength` 未校准时先从仓库补拉基准，再走长度比较
- **检查状态永久卡死**：`connectNow()` / `refreshState()` 增加 20 秒整体超时，超时后正常返回

### 新增

- **发布脚本**：`scripts/release.sh` 一键 bump 版本 + 更新 CHANGELOG + 打 tag；`scripts/publish-release.sh` 下载 artifact + 创建 release

## v1.1.0 - 2026-09-02

### 新增

- **Windows 原生电源事件唤醒重连**：通过 `WM_POWERBROADCAST` (PBT_APMRESUMEAUTOMATIC) 检测休眠唤醒，自动重新认证
  - 去抖 5 秒防止重复触发
  - 延迟 2 秒等待网络栈恢复
- **有线网络（以太网）支持**：在线但无 SSID 时自动识别为以太网连接
- **Windows NLM 网络事件监听**：后台 netsh 轮询实现事件驱动的网络状态检测
  - 后台线程每 2s 检测连接状态，变化时自动触发认证
  - MethodChannel 提供 SSID 查询
- **集成 EportalAnalyzerFlutter**：Dr.COM eportal 分析工具移入 `tools/EportalAnalyzer/`，清除硬编码账密

### 修复

- **portal 不可达误判**：HTTP 超时从 500ms 放宽至 3s，失败后自动重试 1 次
- **状态同步**：portal 不可达时立即更新 UI 状态为「未连接校园网」
- **NLM 连接检测**：ParseConnected 改为正向检查「已连接」，避免误判
- **设置持久化**：`settings_store.dart` 的 `save()` 改用 `toMap()`，修复 `offlinePageLength` 未被保存的问题
- **在线检测误判**：自动保存指纹可能在已登录状态下存错值，改为用户手动校准离线页面长度
- **焦点变化重复登录**：`_doLogin()` 加入 online 检查，已在线时不发 POST
- **登录成功判断**：302 重定向视为请求成功（不代表登录成功），登录成功通过页面长度变化判断
- **GBK 编码问题**：所有 netsh 命令使用 `chcp 65001` 强制 UTF-8 输出

### 优化

- **项目重命名**：AuinEcjtuWifi → EcjtuAuth，包名 `ecjtu_auth`，Android namespace `cn.kitsunemori.ecjtu_auth`
- **统一登录流程**：消除 `connectNow()`/`connectOnce()` 重复代码
- **在线检测改为长度对比**：更轻量、更可靠
- **超时调整**：700ms → 3s（校园网慢时不超时）
- 设置页新增「在线检测校准」section，用户可手动获取离线页面长度
