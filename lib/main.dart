import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_config.dart';
import 'core/eportal_client.dart';
import 'core/network_checker.dart';
import 'platform/desktop_service.dart';
import 'services/auto_connect.dart';
import 'services/credential_store.dart';
import 'services/settings_store.dart';
import 'ui/account_screen.dart';
import 'ui/app_theme.dart';
import 'ui/home_screen.dart';
import 'ui/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final desktop = DesktopService.instance;
  if (desktop.isDesktop) await desktop.ensureWindow();

  final prefs = await SharedPreferences.getInstance();
  runApp(AuinEcjtuWifiApp(desktop: desktop, prefs: prefs));
}

class AuinEcjtuWifiApp extends StatefulWidget {
  const AuinEcjtuWifiApp({super.key, required this.desktop, required this.prefs});

  final DesktopService desktop;
  final SharedPreferences prefs;

  @override
  State<AuinEcjtuWifiApp> createState() => _AuinEcjtuWifiAppState();
}

class _AuinEcjtuWifiAppState extends State<AuinEcjtuWifiApp> {
  late final AutoConnectService service;

  @override
  void initState() {
    super.initState();
    final eportal = EportalClient(config: const AppConfig());
    service = AutoConnectService(
      eportal: eportal,
      checker: NetworkChecker(eportal: eportal, config: const AppConfig()),
      credentials: CredentialStore(),
      settings: SettingsStore(widget.prefs),
    );
    service.loadSettings().then((_) {
      if (service.settings.autoRetry) {
        service.startAutoRetry();
      }
    });
    widget.desktop.initTray(
      onConnect: () => service.connectOnce(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuinEcjtuWifi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: HomeShell(service: service),
    );
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }
}

/// 底部导航壳：主页 / 账号 / 设置。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.service});

  final AutoConnectService service;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  CredentialStore? _credentialStore;

  CredentialStore get _store =>
      _credentialStore ??= CredentialStore();

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(service: widget.service),
      AccountScreen(credentialStore: _store),
      SettingsScreen(service: widget.service),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('AuinEcjtuWifi', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: '手动检测',
            icon: const Icon(Icons.wifi_find_rounded),
            onPressed: () => widget.service.refreshState(),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        height: 66,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wifi_rounded),
            selectedIcon: Icon(Icons.wifi_rounded),
            label: '连接',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '账号',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
        onDestinationSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}
