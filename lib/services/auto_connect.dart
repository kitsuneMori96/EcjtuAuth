import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/eportal_client.dart';
import '../core/network_checker.dart';
import '../models/net_state.dart';
import '../platform/nlm_service.dart';
import 'credential_store.dart';
import 'settings_store.dart';

/// 连接编排器：状态检测 → 认证 → 复验，支持指数退避自动重试。
class AutoConnectService extends ChangeNotifier {
  AutoConnectService({
    required EportalClient eportal,
    required NetworkChecker checker,
    required CredentialStore credentials,
    required SettingsStore settings,
    NlmService? nlmService,
  })  : _eportal = eportal,
        _checker = checker,
        _credentials = credentials,
        settingsStore = settings,
        _nlmService = nlmService {
    _nlmSubscription = _nlmService?.onNetworkChanged.listen(_onNetworkEvent);
  }

  final EportalClient _eportal;
  final NetworkChecker _checker;
  final CredentialStore _credentials;
  final SettingsStore settingsStore;
  final NlmService? _nlmService;
  StreamSubscription<NlmNetworkEvent>? _nlmSubscription;

  /// 暴露 eportal 客户端（供设置页使用）。
  EportalClient get eportal => _eportal;

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

  /// 从仓库获取最新的离线页面长度。
  static const _repoLengthUrl =
      'https://raw.githubusercontent.com/kitsuneMori96/EcjtuAuth/main/portal_length.txt';

  Future<void> fetchLengthFromRepo() async {
    try {
      final res = await http.get(Uri.parse(_repoLengthUrl))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final length = int.tryParse(res.body.trim());
      if (length == null || length <= 0) return;
      _settingsLoaded = _settingsLoaded.copyWith(offlinePageLength: length);
      await settingsStore.save(_settingsLoaded);
      log('已从仓库获取离线页面长度: $length chars');
    } catch (e) {
      log('从仓库获取长度失败: $e');
    }
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

    // 2. 获取 portal 页面（提取 IP + 判断状态）
    final portalSw = Stopwatch()..start();
    String portalBody;
    try {
      portalBody = await _eportal.fetchPortalPage();
    } catch (e) {
      log('${portalSw.elapsedMilliseconds}ms | portal 不可达: $e');
      _updateState(NetState.noCampusWifi);
      return ConnectOutcome.notOnCampus;
    }
    log('${portalSw.elapsedMilliseconds}ms | portal 获取成功 (${portalBody.length} chars)');

    final ip = _eportal.extractIp(portalBody);
    if (ip == null || ip.isEmpty) {
      log('无法解析本机 IP');
      return ConnectOutcome.authFailed;
    }

    // 同步 offlinePageLength 到 checker
    _checker.offlinePageLength = _settingsLoaded.offlinePageLength;

    // 判断在线状态
    if (_checker.offlinePageLength != null && portalBody.length != _checker.offlinePageLength) {
      _attempt = 0;
      _updateState(NetState.online);
      return ConnectOutcome.alreadyOnline;
    }

    // 4. 登录（尽可能快）
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
    // 同步 offlinePageLength 到 checker
    _checker.offlinePageLength = _settingsLoaded.offlinePageLength;

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

  /// NLM 网络事件回调：网络变化时检测并重连。
  void _onNetworkEvent(NlmNetworkEvent event) {
    log('NLM 事件: ${event.event} (ssid=${event.ssid})');
    if (event.isWake) {
      final now = DateTime.now();
      if (_lastWakeAt != null && now.difference(_lastWakeAt!) < const Duration(seconds: 5)) {
        log('唤醒事件去抖，忽略');
        return;
      }
      _lastWakeAt = now;
      log('检测到休眠唤醒，2 秒后重新认证...');
      Future.delayed(const Duration(seconds: 2), () {
        if (state != NetState.online) reconnectAfterWake();
      });
    } else if (event.isConnected) {
      connectOnce();
    } else if (event.isDisconnected) {
      _updateState(NetState.noCampusWifi);
    }
  }

  DateTime? _lastWakeAt;

  /// 休眠唤醒后强制重新认证：延迟等待网络就绪，再走 connectNow。
  Future<void> reconnectAfterWake() async {
    _updateState(NetState.checking);
    await connectNow();
  }

  /// 由平台层注入的 WiFi 名获取函数（测试中可置 null）。
  static Future<String?> Function()? currentSsid;

  @override
  void dispose() {
    _retryTimer?.cancel();
    _nlmSubscription?.cancel();
    super.dispose();
  }
}
