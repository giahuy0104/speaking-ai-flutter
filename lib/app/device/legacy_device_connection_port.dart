import 'dart:async';
import '../../core/audio/hfp_audio_control.dart';
import '../../core/device/aiv0_ble_control.dart';
import '../../domain/device/device_connection.dart';
import '../../features/conversation/presentation/conversation_controller.dart';

/// Temporary migration adapter. Reuses validated native transports, microphone
/// association and history without making the new service depend on a view.
/// The legacy app still owns/disposes these shared objects.
class LegacyDeviceConnectionPort implements DeviceConnectionPort {
  LegacyDeviceConnectionPort({
    required this.ble,
    required this.audio,
    required this.controller,
    required this.android,
    required this.prepare,
  }) {
    controller.addListener(_changed);
    _bleSubscription = ble.statusStream.listen((_) => _changed());
  }
  final MethodChannelAiv0BleControl ble;
  final HfpAudioControl? audio;
  final ConversationController controller;
  @override
  final bool android;
  final Future<DeviceIssue?> Function(bool interactive) prepare;
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<Aiv0BleStatus> _bleSubscription;
  bool _audioPaired = false;
  bool _audioConnected = false;
  int _generation = 0;
  void Function()? _cancelPairVerification;
  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;
  @override
  DeviceSnapshot get snapshot => DeviceSnapshot(
    mainReady: controller.canUseAiv0Ble,
    mainId: ble.status.deviceId,
    audioId: controller.hfpAudioStatus.deviceId,
    batteryPercent: ble.status.batteryPercent,
    firmwareRevision: ble.status.firmwareRevision,
    audioReady: controller.isHomiAudioReady,
    audioPaired: _audioPaired || controller.isHomiAudioReady,
    audioConnected: _audioConnected || controller.isHomiAudioReady,
    routeActive: controller.hfpAudioStatus.routeActive,
    name: ble.status.deviceName ?? controller.hfpAudioStatus.deviceName,
  );
  @override
  Future<DeviceIssue?> prepareAccess({required bool interactive}) =>
      prepare(interactive);
  @override
  Future<void> resumeAutomaticConnection() =>
      controller.resumeAutomaticDeviceConnection();
  @override
  Future<void> refreshAudioPairing() async {
    if (!android) return;
    final generation = _generation;
    try {
      final devices = await audio?.findDevices() ?? const <HfpAudioDevice>[];
      if (generation != _generation) return;
      final homi = devices.where((d) => isRecognizedHomiMicrophoneName(d.name));
      _audioPaired = homi.isNotEmpty;
      _audioConnected = homi.any((d) => d.isConnected);
      _changed();
    } catch (_) {
      /* Pairing inspection must not invalidate verified MAIN. */
    }
  }

  @override
  Future<bool> connectMain({required bool interactive}) async {
    final generation = _generation;
    final connectedIds = <String>[];
    if (android) {
      try {
        final devices = await audio?.findDevices() ?? const <HfpAudioDevice>[];
        connectedIds.addAll(
          devices
              .where(
                (d) => d.isConnected && isRecognizedHomiMicrophoneName(d.name),
              )
              .map((d) => d.id),
        );
      } catch (_) {
        /* BLE scan is still available without an HFP inventory. */
      }
    }
    if (generation != _generation) return false;
    if (android) _audioConnected = connectedIds.isNotEmpty;
    // Pairing happens in system Bluetooth settings (onboarding guide), as on
    // iOS. An in-app Classic bond left HM-D001's BLE MAIN undiscoverable on
    // real Android phones until the Bluetooth stack restarted.
    return ble.autoConnectKnownOrNearby(
      userInitiated: interactive,
      connectedHfpDeviceIds: connectedIds,
      onlyDeviceId: !interactive && controller.isHomiAudioReady
          ? controller.verifiedHomiBleDeviceId
          : null,
    );
  }

  /// Observe system pairing/profile state without selecting or routing a mic.
  /// This bounded transition belongs only to the onboarding pilot. A profile
  /// timeout must not prevent an independent, verifiable MAIN from connecting.
  Future<List<String>> _verifyPairing(
    String deviceId,
    bool bonded, {
    required bool waitForProfile,
  }) async {
    final generation = _generation;
    _cancelPairVerification?.call();
    final result = Completer<List<String>>();
    Timer? poll;
    Timer? deadline;
    bool current() => generation == _generation && !result.isCompleted;
    void finish([List<String> ids = const []]) {
      if (!result.isCompleted) result.complete(ids);
      poll?.cancel();
      deadline?.cancel();
    }

    void cancel() => finish();
    _cancelPairVerification = cancel;
    // Publish the confirmed bond immediately, even while HFP enumeration is
    // still catching up. It never sets audioReady or mainReady.
    if (bonded) {
      _audioPaired = true;
      _changed();
    }
    Future<void> inspect() async {
      try {
        final adapter = await ble.readBluetoothAdapterState();
        if (!current()) return;
        if (adapter == Aiv0BluetoothAdapterState.poweredOff ||
            adapter == Aiv0BluetoothAdapterState.resetting ||
            adapter == Aiv0BluetoothAdapterState.unauthorized ||
            adapter == Aiv0BluetoothAdapterState.unsupported) {
          finish();
          return;
        }
        final devices = await audio?.findDevices() ?? const <HfpAudioDevice>[];
        if (!current()) return;
        final matching = devices.where(
          (d) => d.id.trim().toUpperCase() == deviceId.trim().toUpperCase(),
        );
        _audioPaired = bonded || matching.isNotEmpty;
        _changed();
        final connected = matching
            .where((d) => d.isConnected)
            .map((d) => d.id)
            .toList();
        if (connected.isNotEmpty || !bonded || !waitForProfile) {
          finish(connected);
        } else {
          poll = Timer(const Duration(milliseconds: 250), inspect);
        }
      } catch (_) {
        // Missing/failed profile enumeration cannot invalidate a verified bond
        // or stop BLE. Do not infer an identity from a failed inventory read.
        if (current()) finish();
      }
    }

    deadline = Timer(
      Duration(seconds: waitForProfile && bonded ? 5 : 1),
      finish,
    );
    unawaited(inspect());
    try {
      return await result.future;
    } finally {
      poll?.cancel();
      deadline.cancel();
      if (identical(_cancelPairVerification, cancel)) {
        _cancelPairVerification = null;
      }
    }
  }

  @override
  Future<void> pairConnectedMain() async {
    final generation = _generation;
    final id = ble.status.deviceId;
    final bonded = await ble.requestSystemPairingForConnectedDevice();
    if (generation != _generation) return;
    if (android && id != null) {
      await _verifyPairing(id, bonded, waitForProfile: true);
    }
  }

  @override
  Future<bool> autoSelectAudio() => controller.autoConnectH20Hfp(
    bleDeviceName: ble.status.deviceName,
    requireConnected: android,
  );
  @override
  Future<List<DeviceMicrophone>> findMicrophones() async =>
      (await controller.findHfpDevices())
          .map(
            (d) => DeviceMicrophone(
              id: d.id,
              name: d.name,
              connected: d.isConnected,
              needsConfirmation: controller.requiresHomiMicrophoneConfirmation(
                d,
              ),
            ),
          )
          .toList();
  @override
  Future<bool> selectMicrophone(DeviceSelection selection) async {
    final d = selection.device;
    final result = await controller.connectHfpDevice(
      HfpAudioDevice(id: d.id, name: d.name, isConnected: d.connected),
      confirmHomiAssociation: selection.confirmAssociation,
    );
    return result.succeeded;
  }

  @override
  Future<void> cancelAttempt() {
    _generation++;
    _cancelPairVerification?.call();
    return controller.cancelManualDeviceConnection();
  }

  @override
  Future<void> dispose() async {
    _generation++;
    _cancelPairVerification?.call();
    controller.removeListener(_changed);
    await _bleSubscription.cancel();
    await _changes.close();
  }
}
