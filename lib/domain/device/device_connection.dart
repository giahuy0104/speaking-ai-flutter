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

  /// HOMI audio (HFP/A2DP) connected before MAIN. HM-D001 stops advertising
  /// BLE MAIN while Classic audio is up, so audio must be paused first.
  audioBlocksMain,
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
    this.audioConnected = false,
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

  /// A HOMI HFP device is connected at system level (not necessarily
  /// selected as the app microphone).
  final bool audioConnected;
  final bool routeActive;
  final String? mainId;
  final String? audioId;
  final int? batteryPercent;
  final String? firmwareRevision;
  final String? name;
  bool get ready => mainReady && audioReady;

  @override
  bool operator ==(Object other) =>
      other is DeviceSnapshot &&
      other.mainReady == mainReady &&
      other.audioReady == audioReady &&
      other.audioPaired == audioPaired &&
      other.audioConnected == audioConnected &&
      other.routeActive == routeActive &&
      other.mainId == mainId &&
      other.audioId == audioId &&
      other.batteryPercent == batteryPercent &&
      other.firmwareRevision == firmwareRevision &&
      other.name == name;

  @override
  int get hashCode => Object.hash(
    mainReady,
    audioReady,
    audioPaired,
    audioConnected,
    routeActive,
    mainId,
    audioId,
    batteryPercent,
    firmwareRevision,
    name,
  );
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

  @override
  bool operator ==(Object other) =>
      other is DeviceMicrophone &&
      other.id == id &&
      other.name == name &&
      other.connected == connected &&
      other.needsConfirmation == needsConfirmation;

  @override
  int get hashCode => Object.hash(id, name, connected, needsConfirmation);
}

class DeviceSelection {
  const DeviceSelection(this.device, {this.confirmAssociation = false});
  final DeviceMicrophone device;
  final bool confirmAssociation;
}

class DeviceConnectionState {
  const DeviceConnectionState({
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

  /// Value equality lets the service and DeviceBloc drop repeated identical
  /// states (the port reports a change on every ConversationController
  /// notification, most of which leave the device untouched).
  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is DeviceConnectionState &&
      other.stage == stage &&
      other.snapshot == snapshot &&
      other.issue == issue &&
      other.attempt == attempt &&
      _sameMicrophones(other.microphones, microphones);

  @override
  int get hashCode =>
      Object.hash(stage, snapshot, issue, attempt, Object.hashAll(microphones));

  static bool _sameMicrophones(
    List<DeviceMicrophone> a,
    List<DeviceMicrophone> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
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
