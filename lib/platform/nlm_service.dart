import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class NlmNetworkEvent {
  final String event;
  final String ssid;

  const NlmNetworkEvent({required this.event, required this.ssid});

  bool get isConnected => event == 'connected';
  bool get isDisconnected => event == 'disconnected';
  bool get isWake => event == 'wake';
  bool get isSuspend => event == 'suspend';

  @override
  String toString() => 'NlmNetworkEvent($event, ssid=$ssid)';
}

class NlmService {
  static const _eventChannel = EventChannel('ecjtu_auth/network_events');
  static const _methodChannel =
      MethodChannel('ecjtu_auth/network_methods');

  StreamSubscription<Map<dynamic, dynamic>>? _subscription;
  final _controller = StreamController<NlmNetworkEvent>.broadcast();

  Stream<NlmNetworkEvent> get onNetworkChanged => _controller.stream;

  void startListening() {
    if (!Platform.isWindows) return;

    _subscription = _eventChannel.receiveBroadcastStream().map((event) {
      return Map<dynamic, dynamic>.from(event as Map);
    }).listen(
      (data) {
        final event = NlmNetworkEvent(
          event: data['event'] as String? ?? 'unknown',
          ssid: data['ssid'] as String? ?? '',
        );
        _controller.add(event);
      },
      onError: (error) {
        // Silently ignore NLM errors on non-Windows or unsupported systems.
      },
    );
  }

  Future<String?> getCurrentSsid() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await _methodChannel
          .invokeMethod<Map>('getCurrentSsid');
      return result?['ssid'] as String?;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
