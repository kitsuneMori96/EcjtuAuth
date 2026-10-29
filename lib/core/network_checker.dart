import '../models/net_state.dart';
import 'eportal_client.dart';
import 'portal_failure.dart';

/// 一次网络状态检测的结果。
class CheckResult {
  const CheckResult(
    this.state, {
    this.failure,
    this.pageLength,
    this.needsCalibration = false,
  });

  final NetState state;

  /// portal 请求失败原因；成功时为 null。
  final PortalFailure? failure;

  /// 本次 portal 页面长度，便于诊断。
  final int? pageLength;

  /// 尚未校准离线页面长度，无法判断在线状态。
  final bool needsCalibration;
}

/// 网络状态检测器：对比 portal 页面长度与校准值。
///
/// 本类不再主动拉取远端基准——基准由 AutoConnectService 统一获取并持久化，
/// 避免每次检测都产生外网请求、以及基准只写内存不落盘的问题。
class NetworkChecker {
  NetworkChecker({EportalClient? eportal})
    : _eportal = eportal ?? EportalClient();

  final EportalClient _eportal;

  /// 校准后的离线页面长度（由 settings 传入）。
  int? offlinePageLength;

  Future<CheckResult> check({String? portalBody}) async {
    if (portalBody != null) return judge(portalBody);
    try {
      return judge(await _eportal.fetchPortalPage());
    } on PortalException catch (e) {
      return CheckResult(NetState.unknown, failure: e.failure);
    } catch (_) {
      return const CheckResult(
        NetState.unknown,
        failure: PortalFailure.unknown,
      );
    }
  }

  /// 仅做长度比较，不发请求。
  CheckResult judge(String portalBody) {
    final baseline = offlinePageLength;
    if (baseline == null) {
      return CheckResult(
        NetState.unknown,
        pageLength: portalBody.length,
        needsCalibration: true,
      );
    }
    return CheckResult(
      portalBody.length == baseline ? NetState.campusBlocked : NetState.online,
      pageLength: portalBody.length,
    );
  }
}
