import 'dart:io';
import 'package:flutter/widgets.dart' show Size;

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 桌面集成：窗口管理、系统托盘、开机自启。
/// 在非 Windows 平台全部为安全空实现。
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

  Future<void> initTray({
    required void Function() onConnect,
  }) async {
    if (!Platform.isWindows) return;
    onTrayConnect = onConnect;
    onTrayShowWindow = showMainWindow;
    try {
      await _tray.initSystemTray(
      title: 'EcjtuAuth',
        iconPath: 'assets/app_icon.ico',
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
    } catch (_) {
      _trayReady = false;
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
