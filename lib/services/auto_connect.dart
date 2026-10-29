import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/eportal_client.dart';
import '../core/network_checker.dart';
import '../core/portal_failure.dart';
import '../core/portal_length_repository.dart';
import '../models/net_state.dart';
import '../platform/nlm_service.dart';
import 'credential_store.dart';
import 'log_store.dart';
import 'retry_policy.dart';
import 'settings_store.dart';

/// 连接编排器：状态检测 → 认证 → 复验，支持指数退避自动重试。
///
/// 所有连接入口共享同一个 in-flight Future（single-flight），
/// 并发触发不会产生重复登录，也不会再把「正在连接」误当成「已在线」。
class AutoConnectService extends ChangeNotifier {
  AutoConnectService({
    required EportalClient eportal,
    required NetworkChecker checker,
    required CredentialStore credentials,
    required SettingsStore settings,
    NlmService? nlmService,
    Future<String?> Function()? currentSsid,
    Future<(int, String)?> Function()? fetchLength,
    LogStore? logStore,
  }) : _eportal = eportal,
       _checker = checker,
       _credentials = credentials,
       settingsStore = settings,
       _nlmService = nlmService,
       _currentSsid = currentSsid,
       _fetchLength = fetchLength ?? PortalLengthRepository.fetch,
       _logStore = logStore {
    _nlmSubscription = _nlmService?.onNetworkChanged.listen(_onNetworkEvent);
  }

  final EportalClient _eportal;
  final NetworkChecker _checker;
  final CredentialStore _credentials;
  final SettingsStore settingsStore;
  final NlmService? _nlmService;
  final Future<String?> Function()? _currentSsid;
  final Future<(int, String)?> Function() _fetchLength;
  final LogStore? _logStore;
  StreamSubscription<NlmNetworkEvent>? _nlmSubscription;

  NetState state = NetState.checking;

  /// 最近一次检测的补充说明（失败原因、未校准提示等）。
  String? statusDetail;

  final List<String> logLines = [];

  Timer? _retryTimer;
  int _attempt = 0;
  int _authFailStreak = 0;
  bool _refreshing = false;
  bool _disposed = false;
  DateTime? _lastWakeAt;

  Future<ConnectOutcome>? _inFlight;
  Future<int?>? _baselineFetch;

  String? _lastIp;
  String? _lastSsid;

  static const _overallTimeout = Duration(seconds: 20);

  EportalClient get eportal => _eportal;

  AppSettings get settings => _settingsLoaded;

  AppSettings _settingsLoaded = const AppSettings();

  bool get busy => _inFlight != null || _refreshing;

  Future<void> loadSettings() async {
    _settingsLoaded = await settingsStore.load();
    _applyConfig();
    _checker.offlinePageLength = _settingsLoaded.offlinePageLength;
    _seedLogsFromDisk();
    _notify();
  }

  /// 把上次运行留下的日志接回内存列表（[logLines] 是倒序）。
  void _seedLogsFromDisk() {
    final store = _logStore;
    if (store == null || logLines.isNotEmpty) return;
    logLines.addAll(store.recentLines(200).reversed);
  }

  /// 导出落盘日志（含轮转文件），供「复制日志」使用。
  Future<String> exportLogs() async {
    final store = _logStore;
    if (store == null) return logLines.reversed.join('\n');
    final text = await store.exportText();
    if (text.isNotEmpty) return text;
    return logLines.reversed.join('\n');
  }

  /// 从仓库获取最新的离线页面长度（Gitee 优先，GitHub 兜底）并持久化。
  Future<void> fetchLengthFromRepo() async {
    final length = await _ensureBaseline(force: true);
    if (length == null) {
      log('从仓库获取长度失败: Gitee/GitHub 均不可用');
    }
  }

  Future<void> saveSettings(AppSettings s) async {
    final previous = _settingsLoaded;
    _settingsLoaded = s;
    _applyConfig();
    _checker.offlinePageLength = s.offlinePageLength;
    await settingsStore.save(s);
    if (s.autoRetry != previous.autoRetry) {
      if (s.autoRetry) {
        startAutoRetry();
      } else {
        cancelAutoRetry();
      }
    }
    _notify();
  }

  /// 当前 SSID；不可用时返回 null（UI 用）。
  Future<String?> probeSsid() async {
    final ssid = await _readSsid();
    return ssid.isEmpty ? null : ssid;
  }

  void log(String message) {
    if (_disposed) return;
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$ts] $message';
    logLines.insert(0, line);
    if (logLines.length > 200) logLines.removeLast();
    _logStore?.write(line);
    _notify();
  }

  // ─── 统一登录逻辑 ───────────────────────────────────

  Future<ConnectOutcome> _doLogin(Stopwatch totalSw) async {
    final account = await _credentials.read();
    if (account == null || !account.isValid) {
      log('未配置账号，无法认证');
      _updateStatus(state, detail: '未配置账号');
      return ConnectOutcome.authFailed;
    }

    final ssid = await _readSsid();
    final onCampus = _isCampusSsid(ssid);
    _checker.offlinePageLength = _settingsLoaded.offlinePageLength;

    // 1. 获取 portal 页面（提取 IP + 判断状态）
    final portalSw = Stopwatch()..start();
    String? portalBody;
    PortalException? fetchError;
    try {
      portalBody = await _eportal.fetchPortalPage();
      final ip = _eportal.extractIp(portalBody);
      if (ip != null && ip.isNotEmpty) _lastIp = ip;
      log(
        '${portalSw.elapsedMilliseconds}ms | portal 获取成功 '
        '(${portalBody.length} chars, ip=${_lastIp ?? '未知'})',
      );
    } on PortalException catch (e) {
      fetchError = e;
      log(
        '${portalSw.elapsedMilliseconds}ms | portal 不可达: '
        '${e.failure.label} (${e.message})',
      );
    } catch (e) {
      fetchError = PortalException(PortalFailure.unknown, '$e');
      log('${portalSw.elapsedMilliseconds}ms | portal 异常: $e');
    }

    if (fetchError != null) {
      _updateStatus(
        onCampus ? NetState.campusBlocked : NetState.noCampusWifi,
        detail: '${fetchError.failure.label}：${fetchError.message}',
      );
      if (!onCampus) return ConnectOutcome.notOnCampus;
      if (_lastIp == null) {
        log('没有可用的校园网 IP，无法尝试登录');
        return ConnectOutcome.portalUnreachable;
      }
      log('portal 不可达，使用上次 IP ${_lastIp!} 尝试登录');
    } else {
      final body = portalBody!;
      final baseline = await _ensureBaseline();
      if (baseline != null && body.length != baseline) {
        _attempt = 0;
        _authFailStreak = 0;
        _updateStatus(NetState.online);
        log('已在线（页面长度 ${body.length} ≠ 基准 $baseline），跳过登录');
        return ConnectOutcome.alreadyOnline;
      }
      if (baseline == null) {
        log('未校准离线页面长度，登录后可能无法验证结果');
      }
    }

    // 2. 登录
    final ip = _lastIp;
    if (ip == null) {
      log('无法解析本机 IP');
      return ConnectOutcome.authFailed;
    }

    final loginSw = Stopwatch()..start();
    final freeAccess = _isFreeSsid(ssid);
    try {
      final (_, detail) = await _eportal.postLogin(
        ip: ip,
        username: account.username,
        password: account.password,
        operator: account.operator,
        freeAccess: freeAccess,
      );
      log('${loginSw.elapsedMilliseconds}ms | POST 登录 → $detail');
    } on PortalException catch (e) {
      log(
        '${loginSw.elapsedMilliseconds}ms | POST 登录失败: '
        '${e.failure.label} (${e.message})',
      );
      _updateStatus(
        onCampus ? NetState.campusBlocked : NetState.noCampusWifi,
        detail: '${e.failure.label}：${e.message}',
      );
      return ConnectOutcome.portalUnreachable;
    }

    // 3. 等待服务器生效后复验
    await Future.delayed(const Duration(milliseconds: 300));
    return _verify(totalSw);
  }

  Future<ConnectOutcome> _verify(Stopwatch totalSw) async {
    // 认证后网络通常可用，再尝试补一次基准
    await _ensureBaseline();
    _checker.offlinePageLength = _settingsLoaded.offlinePageLength;

    final probeSw = Stopwatch()..start();
    var result = await _safeCheck();
    log('${probeSw.elapsedMilliseconds}ms | 验证 → ${_describe(result)}');
    _applyCheck(result);

    if (result.state == NetState.online) {
      _attempt = 0;
      _authFailStreak = 0;
      log('认证成功 (总耗时 ${totalSw.elapsedMilliseconds}ms)');
      return ConnectOutcome.success;
    }

    await Future.delayed(const Duration(milliseconds: 500));
    probeSw.reset();
    probeSw.start();
    result = await _safeCheck();
    log('${probeSw.elapsedMilliseconds}ms | 二次验证 → ${_describe(result)}');
    _applyCheck(result);

    if (result.state == NetState.online) {
      _attempt = 0;
      _authFailStreak = 0;
      log('认证成功·延迟生效 (总耗时 ${totalSw.elapsedMilliseconds}ms)');
      return ConnectOutcome.success;
    }

    log('认证后仍无外网 (总耗时 ${totalSw.elapsedMilliseconds}ms)');
    if (result.failure != null) return ConnectOutcome.portalUnreachable;
    if (result.needsCalibration) return ConnectOutcome.unverified;
    return ConnectOutcome.authFailed;
  }

  // ─── 入口方法（single-flight）────────────────────────

  /// 快速连接：直接登录 → 验证。
  Future<ConnectOutcome> connectNow() => _single(_connect);

  /// 完整「检测→认证→复验」流程；已在线时直接返回。
  Future<ConnectOutcome> connectOnce() {
    final existing = _inFlight;
    if (existing != null) return existing;
    if (state == NetState.online) {
      return Future.value(ConnectOutcome.alreadyOnline);
    }
    return _single(_connect);
  }

  Future<ConnectOutcome> _single(Future<ConnectOutcome> Function() body) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _run(body);
    _inFlight = future;
    _notify();
    return future;
  }

  Future<ConnectOutcome> _run(Future<ConnectOutcome> Function() body) async {
    try {
      return await body();
    } finally {
      _inFlight = null;
      _notify();
    }
  }

  Future<ConnectOutcome> _connect() async {
    if (state != NetState.online) {
      _updateStatus(NetState.checking, detail: '正在连接…');
    }
    final totalSw = Stopwatch()..start();
    try {
      return await _doLogin(totalSw).timeout(_overallTimeout);
    } on TimeoutException {
      log('连接超时（${_overallTimeout.inSeconds}s），请重试');
      _updateStatus(
        NetState.unknown,
        detail: '连接超时（${_overallTimeout.inSeconds}s）',
      );
      return ConnectOutcome.portalUnreachable;
    } catch (e) {
      log('连接异常: $e');
      _updateStatus(NetState.unknown, detail: '连接异常: $e');
      return ConnectOutcome.failed;
    }
  }

  // ─── 自动重试 ───────────────────────────────────────

  /// 启动指数退避重试循环：10s → 20s → 40s … 封顶 maxRetryDelay。
  ///
  /// 连续认证失败达到上限后自动停止，避免密码错误时无限登录。
  void startAutoRetry() {
    cancelAutoRetry();
    if (!_settingsLoaded.autoRetry) return;
    unawaited(_retryTick());
  }

  Future<void> _retryTick() async {
    if (_disposed) return;
    final outcome = await connectOnce();
    if (_disposed) return;
    if (outcome.isGood) {
      _authFailStreak = 0;
      return;
    }

    if (outcome == ConnectOutcome.authFailed) {
      _authFailStreak += 1;
      if (_policy.authFailuresExceeded(_authFailStreak)) {
        log(
          '连续认证失败 $_authFailStreak 次，已停止自动重试；'
          '请检查学号、密码与运营商',
        );
        _updateStatus(NetState.campusBlocked, detail: '认证失败，请检查账号信息');
        return;
      }
    } else if (outcome == ConnectOutcome.unverified) {
      log('缺少离线页面长度基准，已停止自动重试；请在设置中获取最新长度');
      return;
    } else {
      _authFailStreak = 0;
    }

    final delay = _policy.delayFor(_attempt);
    _attempt += 1;
    log('${outcome.label}，${delay.inSeconds}s 后重试（第 $_attempt 次）');
    _retryTimer = Timer(delay, _retryTick);
  }

  RetryPolicy get _policy => RetryPolicy(
    baseDelaySec: _settingsLoaded.baseRetryDelaySec,
    maxDelaySec: _settingsLoaded.maxRetryDelaySec,
  );

  void cancelAutoRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempt = 0;
  }

  // ─── 状态查询 ───────────────────────────────────────

  Future<NetState> refreshState() async {
    if (_inFlight != null || _refreshing) return state;
    _refreshing = true;
    _notify();
    final sw = Stopwatch()..start();
    try {
      await _readSsid();
      _checker.offlinePageLength = _settingsLoaded.offlinePageLength;
      final result = await _safeCheck().timeout(_overallTimeout);
      _applyCheck(result);
      log('${sw.elapsedMilliseconds}ms | 刷新状态 → ${_describe(result)}');
      return state;
    } on TimeoutException {
      log('状态检测超时（${_overallTimeout.inSeconds}s）');
      _updateStatus(
        NetState.unknown,
        detail: '状态检测超时（${_overallTimeout.inSeconds}s）',
      );
      return state;
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  Future<CheckResult> _safeCheck() async {
    try {
      return await _checker.check();
    } on PortalException catch (e) {
      return CheckResult(NetState.unknown, failure: e.failure);
    } catch (_) {
      return const CheckResult(
        NetState.unknown,
        failure: PortalFailure.unknown,
      );
    }
  }

  // ─── 基准长度 ───────────────────────────────────────

  Future<int?> _ensureBaseline({bool force = false}) {
    final cached = _settingsLoaded.offlinePageLength;
    if (!force && cached != null) return Future.value(cached);

    final inflight = _baselineFetch;
    if (inflight != null) return inflight;

    final future = _fetchBaselineAndPersist();
    _baselineFetch = future;
    return future.whenComplete(() {
      if (identical(_baselineFetch, future)) _baselineFetch = null;
    });
  }

  Future<int?> _fetchBaselineAndPersist() async {
    try {
      final result = await _fetchLength();
      if (result == null) return null;
      final (length, source) = result;
      _settingsLoaded = _settingsLoaded.copyWith(offlinePageLength: length);
      _checker.offlinePageLength = length;
      await settingsStore.save(_settingsLoaded);
      log('已获取离线页面长度: $length chars (via $source)');
      return length;
    } catch (e) {
      log('拉取离线页面长度失败: $e');
      return null;
    }
  }

  // ─── SSID 辅助 ──────────────────────────────────────

  Future<String> _readSsid() async {
    try {
      final raw = await _currentSsid?.call();
      _lastSsid = raw?.trim().replaceAll('"', '') ?? '';
    } catch (_) {
      // 保留上一次已知 SSID
    }
    return _lastSsid ?? '';
  }

  bool _isCampusSsid(String ssid) {
    if (ssid.isEmpty) return true; // 有线/未知时仍尝试 portal 检测
    final value = ssid.toLowerCase();
    final campus = _settingsLoaded.ssidCampus.toLowerCase();
    final free = _settingsLoaded.ssidFree.toLowerCase();
    return (campus.isNotEmpty && value.contains(campus)) ||
        (free.isNotEmpty && value.contains(free));
  }

  bool _isFreeSsid(String ssid) {
    final free = _settingsLoaded.ssidFree.toLowerCase();
    return free.isNotEmpty && ssid.toLowerCase().contains(free);
  }

  // ─── 状态更新 ───────────────────────────────────────

  void _applyConfig() {
    _eportal.config = AppConfig(portalHost: _settingsLoaded.portalHost);
  }

  void _applyCheck(CheckResult result) {
    final onCampus = _isCampusSsid(_lastSsid ?? '');
    NetState visible;
    String? detail;
    if (result.failure != null) {
      visible = onCampus ? NetState.campusBlocked : NetState.noCampusWifi;
      detail = result.failure!.label;
    } else if (result.needsCalibration) {
      visible = NetState.unknown;
      detail = '未校准离线页面长度，请在设置中获取最新长度';
    } else {
      visible = result.state;
    }
    _updateStatus(visible, detail: detail);
  }

  String _describe(CheckResult result) {
    final parts = <String>[result.state.label];
    if (result.pageLength != null) parts.add('${result.pageLength} chars');
    if (result.failure != null) parts.add(result.failure!.label);
    if (result.needsCalibration) parts.add('未校准');
    return parts.join(' | ');
  }

  void _updateStatus(NetState next, {String? detail}) {
    statusDetail = detail;
    state = next;
    _notify();
  }

  // ─── 网络事件 ───────────────────────────────────────

  void _onNetworkEvent(NlmNetworkEvent event) {
    if (_disposed) return;
    log('NLM 事件: ${event.event} (ssid=${event.ssid})');
    if (event.ssid.isNotEmpty) {
      _lastSsid = event.ssid.trim().replaceAll('"', '');
    }

    if (event.isWake) {
      final now = DateTime.now();
      if (_lastWakeAt != null &&
          now.difference(_lastWakeAt!) < const Duration(seconds: 5)) {
        log('唤醒事件去抖，忽略');
        return;
      }
      _lastWakeAt = now;
      _updateStatus(NetState.checking, detail: '检测到休眠唤醒');
      log('检测到休眠唤醒，2 秒后重新认证...');
      Timer(const Duration(seconds: 2), () {
        if (_disposed) return;
        if (state != NetState.online) unawaited(reconnectAfterWake());
      });
    } else if (event.isConnected) {
      startAutoRetry();
      unawaited(connectOnce());
    } else if (event.isDisconnected) {
      _updateStatus(NetState.noCampusWifi, detail: '网络已断开');
      cancelAutoRetry();
    }
  }

  /// 休眠唤醒后强制重新认证：最多重试 3 次，间隔 5 秒。
  Future<void> reconnectAfterWake() async {
    _updateStatus(NetState.checking, detail: '唤醒后重新认证');
    for (var i = 0; i < 3; i++) {
      final outcome = await connectNow();
      if (outcome.isGood) {
        log('唤醒后认证成功');
        return;
      }
      if (i < 2) {
        log('唤醒后认证失败，5 秒后重试 (${i + 1}/3)...');
        await Future.delayed(const Duration(seconds: 5));
        if (_disposed) return;
      }
    }
    log('唤醒后认证最终失败，请手动重试');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _nlmSubscription?.cancel();
    super.dispose();
  }
}
