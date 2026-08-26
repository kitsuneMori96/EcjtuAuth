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
  bool _userLoggedOut = false;
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

  /// 单次「检测→认证→复验」流程。
  ///
  /// [auto] 为 true 表示由自动机制触发（回前台 / 重试循环），
  /// 用户主动注销后此类调用会被忽略，直至用户手动发起连接。
  Future<ConnectOutcome> connectOnce({bool auto = false}) async {
    if (busy) return ConnectOutcome.alreadyOnline;
    if (auto && _userLoggedOut) {
      log('已忽略自动连接（用户曾主动注销）');
      return ConnectOutcome.alreadyOnline;
    }
    _userLoggedOut = false;
    busy = true;
    notifyListeners();
    try {
      return await _connectOnceInner();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<ConnectOutcome> _connectOnceInner() async {
    var netState = await _safeCheck();
    _updateState(netState);

    if (netState == NetState.noCampusWifi) {
      return ConnectOutcome.notOnCampus;
    }
    if (netState == NetState.online) {
      _attempt = 0;
      return ConnectOutcome.alreadyOnline;
    }

    final account = await _credentials.read();
    if (account == null || !account.isValid) {
      log('未配置账号，无法认证');
      return ConnectOutcome.authFailed;
    }

    final freeAccess = await _isFreeSsid();
    try {
      await _eportal.postLogin(
        username: account.username,
        password: account.password,
        operator: account.operator,
        freeAccess: freeAccess,
      );
    } on EportalException catch (e) {
      log('认证请求失败：${e.message}');
      return ConnectOutcome.authFailed;
    } catch (e) {
      log('认证请求异常：$e');
      return ConnectOutcome.authFailed;
    }

    netState = await _safeCheck();
    _updateState(netState);
    if (netState == NetState.online) {
      _attempt = 0;
      log('认证成功');
      return ConnectOutcome.success;
    }
    log('认证后仍无外网，请检查学号/密码/运营商');
    return ConnectOutcome.authFailed;
  }

  /// 启动指数退避重试循环：10s → 20s → 40s … 封顶 maxRetryDelay。
  Future<void> startAutoRetry() async {
    await loadSettings();
    cancelAutoRetry();
    if (!_settingsLoaded.autoRetry) return;

    Future<void> tick() async {
      final outcome = await connectOnce(auto: true);
      if (outcome.isGood) return;
      final base = _settingsLoaded.baseRetryDelay.inSeconds;
      final cap = _settingsLoaded.maxRetryDelay.inSeconds;
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

  Future<NetState> refreshState() async {
    if (busy) return state;
    busy = true;
    notifyListeners();
    try {
      final s = await _safeCheck();
      _updateState(s);
      return s;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 注销并做连通性实测：HTTP 2xx 不代表注销生效，
  /// 以探测外网是否仍可达为准。
  Future<bool> logout() async {
    if (busy) return false;
    busy = true;
    notifyListeners();
    try {
      final (httpOk, detail) = await _eportal.logout();
      await Future.delayed(const Duration(milliseconds: 800));
      final stillOnline = await _checker.probeInternet();

      if (httpOk && !stillOnline) {
        cancelAutoRetry();
        _userLoggedOut = true;
        log('已注销校园网（自动重连已暂停）');
        return true;
      }

      cancelAutoRetry();
      _userLoggedOut = true;
      if (httpOk) {
        log('服务器已响应但外网仍可访问，注销可能未生效：$detail');
      } else {
        log('注销请求失败：$detail');
      }
      return false;
    } on EportalException catch (e) {
      log('注销失败：${e.message}');
      return false;
    } catch (e) {
      log('注销异常：$e');
      return false;
    } finally {
      busy = false;
      await refreshState();
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
