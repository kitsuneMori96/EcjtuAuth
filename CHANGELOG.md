# 更新日志

## v1.0.2 - 2026-08-26

### 修复

- **注销接口返回 HTTP 203 被误判失败**：Dr.COM eportal 注销接口返回 203（Non-Authoritative Information）而非 200，现放宽为 2xx 即视为成功
- **最小化到托盘未生效**：补设 `setPreventClose(true)`，点击窗口关闭按钮改为隐藏到托盘；托盘左键单击 / 菜单可恢复窗口，右键菜单含「立即连接」「退出」

### 界面

- 移除账号页顶部的「凭据加密存储」提示卡片

### 测试

- 新增注销接口 203 状态码单元测试

## v1.0.1 - 2026-08-26

### 修复

- **注销校园网失败**：已在线状态下认证首页通常不含有效会话标识（`olmac`），注销改为双策略——优先 mac 版，失败自动回退本机 IP 版
- `olmac` 解析兼容单引号 / 双引号 / 等号空白等页面写法差异
- 注销失败原因逐环节写入运行日志，替代笼统的「注销失败」提示
- Windows 构建修复：新版 MSVC 对 `permission_handler_windows` 报 STL1011 硬错误，已在 CMake 全树抑制
- Android `compileSdk` 提升至 37，满足 `permission_handler` 要求

### 优化

- 注销成功后自动暂停重连循环，避免几秒内被重新认证上线

## v1.0.0 - 2026-08-26

### 首个发布版本

基于 [Apauto-to-all/AutoAuthorize](https://github.com/Apauto-to-all/AutoAuthorize) 全面重写的 ECJTU 校园网自动认证工具，单一 Flutter 代码库覆盖 Windows 与 Android。

### 相比原项目的改进

- 凭据经系统级加密存储（Android Keystore / Windows DPAPI），不再明文 JSON 落盘
- 单一 Flutter 代码库替代原项目 PySide2（已停维护）+ Flutter 双栈
- 三态网络检测（未连校园网 / 待认证 / 在线）+ 指数退避自动重试 + 运行日志
- 认证服务器地址、SSID 全部可在应用内修改，不再硬编码
- GitHub Actions 自动构建发布，替代蓝奏云手动上传
- 核心协议层单元测试覆盖

### 功能

- 一键认证 `ECJTU-Stu`（计费）与 `EcjtuLib_Free`（图书馆免费）
- 支持移动 / 电信 / 联通运营商后缀
- Windows：托盘常驻、开机自启、断线自动重连
- Android：回到前台自动连接
- 手动注销校园网会话
- Material 3 界面，明暗主题自适应
