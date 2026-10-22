import 'dart:async';

enum DeviceStage {
  idle,
  checkingAccess,
  connectingMain,
  preparingAudio,
  choosingMicrophone,
  ready,
  incomplete,
  cancelled,
  failed,
}

enum DeviceIssue {
  consentRequired,
  permissionRequired,
  bluetoothOff,
  unsupported,
  mainUnavailable,
  audioUnavailable,
  selectionRequired,
  timedOut,
  transportFailure,
}

class DeviceSnapshot {
  const DeviceSnapshot({
    this.mainReady = false,
    this.audioReady = false,
    this.audioPaired = false,
    this.routeActive = false,
    this.mainId,
    this.audioId,
    this.batteryPercent,
    this.firmwareRevision,
    this.name,
  });
  final bool mainReady;
  final bool audioReady;
  final bool audioPaired;
  final bool routeActive;
  final String? mainId;
  final String? audioId;
  final int? batteryPercent;
  final String? firmwareRevision;
  final String? name;
  bool get ready => mainReady && audioReady;
}

class DeviceMicrophone {
  const DeviceMicrophone({
    required this.id,
    required this.name,
    required this.connected,
    this.needsConfirmation = false,
  });
  final String id;
  final String name;
  final bool connected;
  final bool needsConfirmation;
}

class DeviceSelection {
  const DeviceSelection(this.device, {this.confirmAssociation = false});
  final DeviceMicrophone device;
  final bool confirmAssociation;
}

class DeviceState {
  const DeviceState({
    this.stage = DeviceStage.idle,
    this.snapshot = const DeviceSnapshot(),
    this.issue,
    this.attempt = 0,
    this.microphones = const [],
  });
  final DeviceStage stage;
  final DeviceSnapshot snapshot;
  final DeviceIssue? issue;
  final int attempt;
  final List<DeviceMicrophone> microphones;
  bool get busy => switch (stage) {
    DeviceStage.checkingAccess ||
    DeviceStage.connectingMain ||
    DeviceStage.preparingAudio ||
    DeviceStage.choosingMicrophone => true,
    _ => false,
  };
}

/// Migration boundary. Native BLE/HFP and persisted identity remain in their
/// existing adapters; no Flutter context or presentation callback crosses here.
abstract interface class DeviceConnectionPort {
  DeviceSnapshot get snapshot;
  Stream<void> get changes;
  bool get android;
  Future<DeviceIssue?> prepareAccess({required bool interactive});
  Future<void> resumeAutomaticConnection();
  Future<void> refreshAudioPairing();
  Future<bool> connectMain({required bool interactive});
  Future<void> pairConnectedMain();
  Future<bool> autoSelectAudio();
  Future<List<DeviceMicrophone>> findMicrophones();
  Future<bool> selectMicrophone(DeviceSelection selection);
  Future<void> cancelAttempt();
  Future<void> dispose();
}
