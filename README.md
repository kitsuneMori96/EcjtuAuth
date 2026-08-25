<div align="center">

# AuinEcjtuWifi

**ECJTU 校园网自动认证工具 · Windows + Android**

基于 Flutter 的 [Apauto-to-all/AutoAuthorize](https://github.com/Apauto-to-all/AutoAuthorize) 重构优化版

</div>

## 相比原项目的优化

| 方面 | 原项目 | 本项目 |
|---|---|---|
| 凭据存储 | 明文 JSON 落盘 C 盘 | `flutter_secure_storage` 系统级加密（Android Keystore / Windows DPAPI） |
| 技术栈 | PySide2（已停止维护）+ Flutter 两套代码 | 单一 Flutter 代码库覆盖双端 |
| 断线处理 | 固定分钟轮询、失败无感知 | 三态检测 + 指数退避自动重试 + 运行日志 |
| 可配置性 | 认证 IP / SSID 硬编码 | 全部可在设置页修改并持久化 |
| 分发 | 蓝奏云手动上传 | GitHub Actions 自动构建发布 |
| 质量 | 无测试 | 核心协议层单元测试 + flutter analyze |

## 功能

- 一键认证 ECJTU 校园网（`ECJTU-Stu`）与图书馆免费网络（`EcjtuLib_Free`）
- 支持移动 / 电信 / 联通运营商后缀
- Windows 托盘常驻、最小化到托盘、开机自启
- Android 回到前台自动连接
- 注销校园网会话
- 明暗主题自适应 Material 3 界面

## 使用

1. 连接校园网 WiFi，在「账号」页填写学号、密码与运营商并保存；
2. 回到「连接」页点击「一键认证」，或等待自动重试；
3. 「设置」页可调整认证服务器地址、SSID、自动重连与自启行为。

> Android 端识别 WiFi 名称需要「位置信息」权限（系统限制）；认证时请关闭移动数据。

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
git tag v1.0.0 && git push origin v1.0.0
# → Releases 页产出 AuinEcjtuWifi-android.apk 与 AuinEcjtuWifi-windows-x64.zip
```

## 许可

MIT License，继承自原项目。
