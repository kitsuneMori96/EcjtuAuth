import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show Size;

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 桌面集成：窗口管理、系统托盘、开机自启。
/// 在非 Windows 平台全部为安全空实现。
///
/// 单实例：`windows/runner/main.cpp` 启动时持有
/// `Local\EcjtuAuth_SingleInstance` 互斥量，检测到已有实例会先
/// `SW_RESTORE` + `SetForegroundWindow` 唤起已有窗口再退出。
/// 因此 Dart 侧无需做「防双开」判断，也**不会**出现两个实例各持一份
/// 托盘与 NLM 监听；若未来要支持多开，必须同步移除 C++ 侧互斥量。
class DesktopService with WindowListener {
  DesktopService._();

  static final instance = DesktopService._();

  final SystemTray _tray = SystemTray();
  bool _trayReady = false;

  void Function()? onTrayConnect;
  void Function()? onTrayShowWindow;

  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> ensureWindow() async {
    if (!isDesktop) return;
    windowManager.addListener(this);
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(430, 760),
      minimumSize: Size(360, 560),
      center: true,
      title: 'EcjtuAuth',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    if (Platform.isWindows) {
      await windowManager.setPreventClose(true);
    }
  }

  Future<void> showMainWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// 解析托盘图标路径。
  ///
  /// `system_tray` 通过 Win32 `LoadImage` 按**文件路径**加载图标，
  /// release 构建中资产实际位于 `<exe目录>/data/flutter_assets/assets/`，
  /// 直接用相对路径 `assets/app_icon.ico` 会失败（CWD 是启动目录而非 exe 目录）。
  static String? resolveTrayIconPath() {
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$exeDir${sep}data${sep}flutter_assets${sep}assets${sep}app_icon.ico',
      '${Directory.current.path}${sep}assets${sep}app_icon.ico',
      '$exeDir${sep}assets${sep}app_icon.ico',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    debugPrint('[DesktopService] 托盘图标未找到，已尝试: ${candidates.join(' | ')}');
    return null;
  }

  Future<void> initTray({
    required void Function() onConnect,
  }) async {
    if (!Platform.isWindows) return;
    onTrayConnect = onConnect;
    onTrayShowWindow = showMainWindow;
    try {
      await _tray.initSystemTray(
        title: 'EcjtuAuth',
        iconPath: resolveTrayIconPath() ?? 'assets/app_icon.ico',
        toolTip: 'EcjtuAuth - ECJTU 校园网助手',
      );
      final menu = Menu()
        ..buildFrom([
          MenuItemLabel(label: '打开主界面', onClicked: (_) => showMainWindow()),
          MenuItemLabel(label: '立即连接', onClicked: (_) => onConnect()),
          MenuSeparator(),
          MenuItemLabel(label: '退出', onClicked: (_) async {
            await _tray.destroy();
            await windowManager.destroy();
          }),
        ]);
      await _tray.setContextMenu(menu);
      await _tray.setToolTip('EcjtuAuth');
      _tray.registerSystemTrayEventHandler((eventName) {
        switch (eventName) {
          case kSystemTrayEventClick:
            showMainWindow();
            break;
          case kSystemTrayEventRightClick:
            _tray.popUpContextMenu();
            break;
        }
      });
      _trayReady = true;
    } catch (e, st) {
      _trayReady = false;
      debugPrint('[DesktopService] 托盘初始化失败: $e\n$st');
    }
  }

  /// 最小化到托盘而非退出（仅托盘就绪的 Windows 生效）。
  @override
  void onWindowClose() async {
    if (_trayReady) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }

  Future<void> setLaunchAtStartup(bool enable) async {
    if (!Platform.isWindows) return;
    await configureLaunchAtStartup(enable);
  }

  static Future<void> configureLaunchAtStartup(bool enable) async {
    final info = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: info.appName,
      appPath: Platform.resolvedExecutable,
    );
    if (enable) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  static Future<bool> launchAtStartupIsEnabled() async {
    try {
      return await launchAtStartup.isEnabled();
    } catch (_) {
      return false;
    }
  }
}
