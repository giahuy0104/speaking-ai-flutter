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
  });

  factory H20ConnectionState.from({
    required BluetoothAudioStatus hfpStatus,
    required Aiv0BleStatus bleStatus,
    bool hfpInputSelected = true,
    bool mainTurnActive = false,
  }) {
    final hfpSelected = hfpInputSelected && hfpStatus.deviceId != null;
    // A connected, selected HFP profile is ready for an idle H20. SCO is
    // intentionally opened only while HOMI speaks or listens; requiring an
    // always-active route here made a healthy idle headset look disconnected.
    final hfpReady = hfpSelected && hfpStatus.isConnected;
    final routeActive = hfpReady && hfpStatus.routeActive;
    final bleReady = bleStatus.isConnected;
    final phase = mainTurnActive && routeActive
        ? H20ConnectionPhase.mainTurnActive
        : hfpReady && bleReady
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
    );
  }

  final H20ConnectionPhase phase;
  final bool hfpSelected;
  final bool hfpReady;
  final bool routeActive;
  final bool bleReady;

  bool get isH20Ready => hfpReady && bleReady;

  /// Whether a physical H20 MAIN press may start the strict HFP turn.
  ///
  /// The MAIN turn may start only after both independent transports have been
  /// confirmed. The turn then opens and authoritatively verifies SCO/HFP; a
  /// route failure must not fall back to the phone microphone.
  bool get canStartStrictHfpTurn => hfpReady && bleReady;
}
