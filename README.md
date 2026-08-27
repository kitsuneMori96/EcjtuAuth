<div align="center">

# AuinEcjtuWifi

**ECJTU 校园网自动认证工具 · Windows + Android**

基于 Flutter 的 [Apauto-to-all/AutoAuthorize](https://github.com/Apauto-to-all/AutoAuthorize) 重构优化版

</div>

> [!WARNING]
> **Beta 预发布版本** — 项目仍在积极开发中，功能与稳定性尚在实机验证，可能存在未知问题。
> 欢迎试用并[提交 Issue](https://github.com/kitsuneMori96/AuinEcjtuWifi/issues) 反馈。

## 在线检测原理

本工具通过对比 Dr.COM eportal 认证服务器返回的 portal 页面长度来判断在线状态：

| 状态 | portal 页面特征 |
|---|---|
| 离线（未认证） | 登录页，固定长度（如 3661 chars） |
| 在线（已认证） | 页面内容变化，长度不同（如 3440 chars） |

检测流程：
1. GET `http://172.16.2.100/` 获取 portal 页面
2. 对比响应长度与预存的离线页面长度
3. 长度不同 → 在线；长度相同 → 离线

> 服务器对所有 HTTP 请求返回相同的登录页（captive portal 劫持），登录成功后页面内容会变化。
> 这个变化是判断在线状态的唯一可靠依据。

## 使用

### 首次使用

1. 连接校园网 WiFi（`ECJTU-Stu` 或 `EcjtuLib_Free`）
2. 在「账号」页填写学号、密码与运营商并保存
3. 进入「设置」页，点击「从仓库获取最新长度」获取离线页面长度
4. 回到「连接」页，软件会自动检测并认证

### 日常使用

- 启动时自动检测并认证
- Android 回到前台时自动检测
- Windows 托盘常驻，支持开机自启
- 失败后按指数退避间隔自动重试

### 如果认证状态判断有误

进入「设置」页，点击「从仓库获取最新长度」更新离线页面长度。

> 服务器页面可能更新导致长度变化，此时需要重新获取。

## 功能

- 一键认证 ECJTU 校园网与图书馆免费网络
- 支持移动 / 电信 / 联通运营商后缀
- Windows 托盘常驻、最小化到托盘、开机自启
- Android 回到前台自动连接
- 明暗主题自适应 Material 3 界面
- 在线状态实时检测（portal 页面长度对比）

## 技术细节

### 认证协议

```
GET  http://172.16.2.100/          → 获取 portal 页面 + 提取本机 IP
POST http://172.16.2.100:801/eportal/?c=ACSetting&a=Login&...  → 登录
     响应 302 Moved Temporarily    → 请求成功（不代表登录成功）
GET  http://172.16.2.100/          → 对比页面长度判断是否登录成功
```

### 关键发现

- 登录 POST 无论账密正确与否都返回 302
- 离线页面固定 3661 chars，在线页面 3440 chars
- 页面长度变化是判断登录成功的唯一可靠依据

### 项目结构

```
lib/
├── core/
│   ├── app_config.dart        # 全局配置（服务器地址、超时等）
│   ├── eportal_client.dart    # Dr.COM eportal 协议客户端
│   └── network_checker.dart   # 网络状态检测（页面长度对比）
├── models/
│   ├── campus_account.dart    # 校园网账号模型
│   ├── net_state.dart         # 网络状态枚举
│   └── operator.dart          # 运营商枚举
├── platform/
│   ├── desktop_service.dart   # Windows 托盘、开机自启
│   └── wifi_probe.dart        # WiFi 名称获取
├── services/
│   ├── auto_connect.dart      # 连接编排器（核心流程）
│   ├── credential_store.dart  # 凭据存储（加密）
│   └── settings_store.dart    # 设置持久化
└── ui/
    ├── home_screen.dart       # 主页（状态卡片 + 日志）
    ├── account_screen.dart    # 账号设置
    ├── settings_screen.dart   # 系统设置 + 在线检测校准
    └── widgets/               # 可复用组件
```

## 开发

```bash
flutter pub get
flutter analyze
flutter test          # 协议核心单元测试
flutter run           # 或 -d windows / -d android
```

## 构建

打 tag 推送后由 GitHub Actions 自动构建：

```bash
git tag v1.1.0-beta.2 && git push origin v1.1.0-beta.2
# → Releases 页产出 AuinEcjtuWifi-android.apk 与 AuinEcjtuWifi-windows-x64.zip
```

## 许可

MIT License，继承自原项目。
