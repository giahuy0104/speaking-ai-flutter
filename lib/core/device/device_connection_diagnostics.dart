import 'dart:async';
import '../../domain/device/device_connection.dart';

/// Local metadata only. A Zone carries the immutable originating attempt across
/// awaits; late native requests cannot inherit a newer connection's identifier.
class DeviceConnectionDiagnostics {
  DeviceConnectionDiagnostics({
    this.enabled = false,
    void Function(Map<String, Object?>)? sink,
    String? sessionId,
  }) : _sink = sink,
       _sessionId =
           sessionId ?? DateTime.now().microsecondsSinceEpoch.toString();

  final bool enabled;
  final void Function(Map<String, Object?>)? _sink;
  final String _sessionId;
  final Map<int, String> _attempts = {};
  static final Object _zoneKey = Object();

  String idFor(int generation) =>
      _attempts[generation] ?? '$_sessionId-$generation';

  void inherit(int generation, int previous) {
    if (!enabled) return;
    _attempts[generation] = idFor(previous);
    // Keep cancellation aliases bounded over long app sessions. Live/late
    // operations carry their immutable ID in the Zone, independently.
    if (_attempts.length > 64) _attempts.remove(_attempts.keys.first);
  }

  T run<T>(int generation, T Function() action) => !enabled
      ? action()
      : runZoned(action, zoneValues: {_zoneKey: (this, idFor(generation))});

  static Map<String, Object?> get channelFields {
    final frame = Zone.current[_zoneKey];
    if (frame is! (DeviceConnectionDiagnostics, String)) return const {};
    return {'attemptId': frame.$2};
  }

  void event(
    int generation,
    String event, [
    Map<String, Object?> fields = const {},
  ]) {
    if (!enabled) return;
    try {
      _sink?.call({
        ...fields,
        'event': event,
        'attemptId': idFor(generation),
        'utcMs': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      // Diagnostics must never change connection/cancellation behavior.
    }
  }

  void state(String layer, DeviceConnectionState state) =>
      event(state.attempt, '$layer.state', {
        'generation': state.attempt,
        'stage': state.stage.name,
        'issue': state.issue?.name,
        'mainReady': state.snapshot.mainReady,
        'mainId': state.snapshot.mainId,
        'audioPaired': state.snapshot.audioPaired,
        'audioConnected': state.snapshot.audioConnected,
        'audioReady': state.snapshot.audioReady,
        'audioId': state.snapshot.audioId,
        'scoRouteActive': state.snapshot.routeActive,
        'firmware': state.snapshot.firmwareRevision,
      });
}
