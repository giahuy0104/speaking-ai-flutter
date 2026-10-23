import '../audio/audio_input.dart';
import 'aiv0_ble_control.dart';

enum H20ConnectionPhase {
  disconnected,
  hfpReady,
  bleReady,
  h20Ready,
  mainTurnActive,
}

/// One app-level view of H20 readiness across its independent HFP and BLE
/// transports. Neither link alone is reported as a fully ready H20.
class H20ConnectionState {
  const H20ConnectionState({
    required this.phase,
    required this.hfpSelected,
    required this.hfpReady,
    required this.routeActive,
    required this.bleReady,
    this.hfpMatchesHomi = false,
  });

  factory H20ConnectionState.from({
    required BluetoothAudioStatus hfpStatus,
    required Aiv0BleStatus bleStatus,
    bool hfpInputSelected = true,
    bool mainTurnActive = false,
    bool? hfpMatchesHomi,
  }) {
    final hfpSelected = hfpInputSelected && hfpStatus.deviceId != null;
    // A connected, selected HFP profile is ready for an idle H20. SCO is
    // intentionally opened only while HOMI speaks or listens; requiring an
    // always-active route here made a healthy idle headset look disconnected.
    final hfpReady = hfpSelected && hfpStatus.isConnected;
    final routeActive = hfpReady && hfpStatus.routeActive;
    final bleReady = bleStatus.isConnected;
    final matchesHomi =
        hfpMatchesHomi ??
        sameConnectionDeviceId(hfpStatus.deviceId, bleStatus.deviceId);
    final phase = mainTurnActive && routeActive
        ? H20ConnectionPhase.mainTurnActive
        : hfpReady && bleReady && matchesHomi
        ? H20ConnectionPhase.h20Ready
        : hfpReady
        ? H20ConnectionPhase.hfpReady
        : bleReady
        ? H20ConnectionPhase.bleReady
        : H20ConnectionPhase.disconnected;
    return H20ConnectionState(
      phase: phase,
      hfpSelected: hfpSelected,
      hfpReady: hfpReady,
      routeActive: routeActive,
      bleReady: bleReady,
      hfpMatchesHomi: matchesHomi,
    );
  }

  final H20ConnectionPhase phase;
  final bool hfpSelected;
  final bool hfpReady;
  final bool routeActive;
  final bool bleReady;

  /// The two transports share an identifier or the parent explicitly confirmed
  /// their association. Device names alone are not proof of a shared device.
  final bool hfpMatchesHomi;

  /// Verified audio stays usable while the independent MAIN link recovers.
  /// The association can come from the last connected BLE device; readiness
  /// still requires the selected HFP profile to be connected right now.
  bool get isHomiAudioReady => hfpReady && hfpMatchesHomi;

  bool get isH20Ready => isHomiAudioReady && bleReady;

  /// Whether a physical H20 MAIN press may start the strict HFP turn.
  ///
  /// The MAIN turn may start only after both independent transports have been
  /// confirmed. The turn then opens and authoritatively verifies SCO/HFP; a
  /// route failure must not fall back to the phone microphone.
  bool get canStartStrictHfpTurn => isH20Ready;
}

bool sameConnectionDeviceId(String? first, String? second) {
  if (first == null || second == null) return false;
  String normalize(String value) {
    final trimmed = value.trim().toLowerCase();
    // Android may format a hardware MAC with or without separators. Keep other
    // platform UIDs intact so unrelated opaque identifiers cannot collapse.
    final compact = trimmed.replaceAll(RegExp('[:-]'), '');
    return RegExp(r'^[0-9a-f]{12}$').hasMatch(compact) ? compact : trimmed;
  }

  final normalized = normalize(first);
  return normalized.isNotEmpty && normalized == normalize(second);
}
