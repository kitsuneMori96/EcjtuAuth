# 更新日志

> 当前处于 **Beta 预发布**阶段，版本号及功能尚在迭代，正式版发布前可能有较多变动。

## v1.1.0 - 2026-08-29

### 新增

- **Windows NLM 网络事件监听**：使用 COM INetworkListManagerEvents 实现事件驱动的网络状态检测
  - 后台 STA 线程监听 NetworkConnected / NetworkDisconnected 事件
  - 网络变化时自动检测在线状态，不在线则触发认证
  - MethodChannel 提供 SSID 查询（替代不可靠的 network_info_plus）
- **集成 EportalAnalyzerFlutter**：Dr.COM eportal 分析工具移入 `tools/EportalAnalyzer/`，清除硬编码账密

### 修复

- **设置持久化**：`settings_store.dart` 的 `save()` 改用 `toMap()`，修复 `offlinePageLength` 未被保存的问题
- **在线检测误判**：自动保存指纹可能在已登录状态下存错值，改为用户手动校准离线页面长度
- **焦点变化重复登录**：`_doLogin()` 加入 online 检查，已在线时不发 POST
- **登录成功判断**：302 重定向视为请求成功（不代表登录成功），登录成功通过页面长度变化判断

### 优化

- **项目重命名**：AuinEcjtuWifi → EcjtuAuth，包名 `ecjtu_auth`，Android namespace `cn.kitsunemori.ecjtu_auth`
- **统一登录流程**：消除 `connectNow()`/`connectOnce()` 重复代码
- **在线检测改为长度对比**：更轻量、更可靠
- **超时调整**：700ms → 500ms
- 设置页新增「在线检测校准」section，用户可手动获取离线页面长度

## v1.0.0 - 2026-08-26

首个发布版本。基于 [Apauto-to-all/AutoAuthorize](https://github.com/Apauto-to-all/AutoAuthorize) 全面重写，单一 Flutter 代码库覆盖 Windows 与 Android。
