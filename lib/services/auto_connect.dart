import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/eportal_client.dart';
import '../core/network_checker.dart';
import '../models/net_state.dart';
import 'credential_store.dart';
import 'settings_store.dart';

/// 连接编排器：状态检测 → 认证 → 复验，支持指数退避自动重试。
class AutoConnectService extends ChangeNotifier {
  AutoConnectService({
    required EportalClient eportal,
    required NetworkChecker checker,
    required CredentialStore credentials,
    required SettingsStore settings,
  })  : _eportal = eportal,
        _checker = checker,
        _credentials = credentials,
        settingsStore = settings;

  final EportalClient _eportal;
  final NetworkChecker _checker;
  final CredentialStore _credentials;
  final SettingsStore settingsStore;

  NetState state = NetState.checking;
  bool busy = false;
  final List<String> logLines = [];

  Timer? _retryTimer;
  int _attempt = 0;

  AppSettings get settings => _settingsLoaded;

  AppSettings _settingsLoaded = const AppSettings();

  Future<void> loadSettings() async {
    _settingsLoaded = await settingsStore.load();
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings s) async {
    _settingsLoaded = s;
    await settingsStore.save(s);
    notifyListeners();
  }

  void log(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    logLines.insert(0, '[$ts] $message');
    if (logLines.length > 200) logLines.removeLast();
    notifyListeners();
  }

  // ─── 统一登录逻辑 ───────────────────────────────────

  Future<ConnectOutcome> _doLogin(Stopwatch totalSw) async {
    // 1. 读取账号
    final account = await _credentials.read();
    if (account == null || !account.isValid) {
      log('未配置账号，无法认证');
      return ConnectOutcome.authFailed;
    }

    // 2. 获取 portal 页面（提取 IP + 保存指纹）
    final checkSw = Stopwatch()..start();
    final netState = await _safeCheck();
    log('${checkSw.elapsedMilliseconds}ms | 检测 → ${netState.label}');
    _updateState(netState);

    if (netState == NetState.noCampusWifi) {
      return ConnectOutcome.notOnCampus;
    }

    if (netState == NetState.online) {
      _attempt = 0;
      return ConnectOutcome.alreadyOnline;
    }

    final ip = _checker.cachedIp;
    if (ip == null || ip.isEmpty) {
      log('无法获取本机 IP');
      return ConnectOutcome.authFailed;
    }

    // 3. 登录（尽可能快）
    final loginSw = Stopwatch()..start();
    final freeAccess = await _isFreeSsid();
    final (httpOk, loginDetail) = await _eportal.postLogin(
      ip: ip,
      username: account.username,
      password: account.password,
      operator: account.operator,
      freeAccess: freeAccess,
    ).catchError((e) {
      return (false, '$e');
    });
    log('${loginSw.elapsedMilliseconds}ms | POST 登录 → $loginDetail');
    if (!httpOk) return ConnectOutcome.authFailed;

    // 4. 等待服务器生效
    await Future.delayed(const Duration(milliseconds: 300));

    // 5. 验证
    return _verify(totalSw);
  }

  Future<ConnectOutcome> _verify(Stopwatch totalSw) async {
    final probeSw = Stopwatch()..start();
    var netState = await _safeCheck();
    log('${probeSw.elapsedMilliseconds}ms | 验证 → ${netState.label}');
    _updateState(netState);

    if (netState == NetState.online) {
      _attempt = 0;
      log('认证成功 (总耗时 ${totalSw.elapsedMilliseconds}ms)');
      return ConnectOutcome.success;
    }

    // 重试一次
    await Future.delayed(const Duration(milliseconds: 500));
    probeSw.reset();
    probeSw.start();
    netState = await _safeCheck();
    log('${probeSw.elapsedMilliseconds}ms | 二次验证 → ${netState.label}');
    _updateState(netState);

    if (netState == NetState.online) {
      _attempt = 0;
      log('认证成功·延迟生效 (总耗时 ${totalSw.elapsedMilliseconds}ms)');
      return ConnectOutcome.success;
    }

    log('认证后仍无外网 (总耗时 ${totalSw.elapsedMilliseconds}ms)');
    return ConnectOutcome.authFailed;
  }

  // ─── 入口方法 ───────────────────────────────────────

  /// 快速连接：直接登录 → 验证。
  ///
  /// 用于启动、回前台、托盘「立即连接」等需要立即响应的场景。
  Future<ConnectOutcome> connectNow() async {
    if (busy) return ConnectOutcome.alreadyOnline;
    busy = true;
    notifyListeners();
    final totalSw = Stopwatch()..start();
    try {
      return await _doLogin(totalSw);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 完整「检测→认证→复验」流程（含初始状态检测）。
  ///
  /// 用于重试循环、手动刷新等需要完整判断的场景。
  Future<ConnectOutcome> connectOnce() async {
    if (busy) return ConnectOutcome.alreadyOnline;
    if (state == NetState.online) return ConnectOutcome.alreadyOnline;
    busy = true;
    notifyListeners();
    final totalSw = Stopwatch()..start();
    try {
      return await _doLogin(totalSw);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ─── 自动重试 ───────────────────────────────────────

  /// 启动指数退避重试循环：10s → 20s → 40s … 封顶 maxRetryDelay。
  Future<void> startAutoRetry() async {
    await loadSettings();
    cancelAutoRetry();
    if (!_settingsLoaded.autoRetry) return;

    Future<void> tick() async {
      final outcome = await connectOnce();
      if (outcome.isGood) return;
      final base = _settingsLoaded.baseRetryDelaySec;
      final cap = _settingsLoaded.maxRetryDelaySec;
      final delaySec = min(cap, base * (1 << min(_attempt, 6)));
      _attempt += 1;
      log('${outcome.label}，${delaySec}s 后重试（第 $_attempt 次）');
      _retryTimer = Timer(Duration(seconds: delaySec), tick);
    }

    unawaited(tick());
  }

  void cancelAutoRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempt = 0;
  }

  // ─── 状态查询 ───────────────────────────────────────

  Future<NetState> refreshState() async {
    if (busy) return state;
    busy = true;
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      final s = await _safeCheck();
      log('${sw.elapsedMilliseconds}ms | 刷新状态 → ${s.label}');
      _updateState(s);
      return s;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<NetState> _safeCheck() async {
    try {
      return await _checker.check();
    } catch (_) {
      return NetState.noCampusWifi;
    }
  }

  Future<bool> _isFreeSsid() async {
    final current = await currentSsid?.call() ?? '';
    final free = _settingsLoaded.ssidFree;
    return current.trim().contains(free);
  }

  void _updateState(NetState s) {
    if (state != s) {
      state = s;
      notifyListeners();
    }
  }

  /// 由平台层注入的 WiFi 名获取函数（测试中可置 null）。
  static Future<String?> Function()? currentSsid;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}
