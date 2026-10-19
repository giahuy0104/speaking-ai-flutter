import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_history.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const bleDevice = Aiv0BleDevice(id: 'ble', name: 'HOMI', rssi: -40);
  const microphone = HfpAudioDevice(
    id: 'mic',
    name: 'HM-D001',
    isConnected: true,
  );

  test(
    'busy manual connect returns busy and cannot report success or save history',
    () async {
      final ble = _Ble();
      final controller = _controller(ble: ble);
      controller.phase = ConversationPhase.recording;
      final result = await controller.connectAiv0Device(bleDevice);
      expect(result.outcome, DeviceConnectionOutcome.busy);
      expect(ble.connectCount, 0);
      expect(controller.lastConnectedBleDevice, isNull);
      controller.phase = ConversationPhase.idle;
      controller.dispose();
    },
  );

  test(
    'native completion without expected connected ID is a failed connection',
    () async {
      final ble = _Ble(connects: false);
      final controller = _controller(ble: ble);
      final result = await controller.connectAiv0Device(bleDevice);
      expect(result.outcome, DeviceConnectionOutcome.failed);
      expect(controller.lastConnectedBleDevice, isNull);
      controller.dispose();
    },
  );

  test(
    'BLE and microphone histories persist independently after disconnect',
    () async {
      final ble = _Ble();
      final hfp = _Hfp();
      final controller = _controller(ble: ble, hfp: hfp);
      expect((await controller.connectAiv0Device(bleDevice)).succeeded, isTrue);
      expect(
        (await controller.connectHfpDevice(
          microphone,
          confirmHomiAssociation: true,
        )).succeeded,
        isTrue,
      );
      expect(controller.isH20Ready, isTrue);
      expect(controller.lastConnectedMicrophone?.bleDeviceId, 'ble');
      expect((await controller.disconnectHfpDevice()).succeeded, isTrue);
      expect((await controller.disconnectAiv0Device()).succeeded, isTrue);
      final history = DeviceConnectionHistoryStore();
      expect((await history.readBle())?.id, 'ble');
      expect((await history.readMicrophone())?.id, 'mic');
      expect((await history.readMicrophone())?.bleDeviceId, 'ble');
      controller.dispose();
    },
  );

  test(
    'same device name does not establish readiness until parent confirms association',
    () async {
      final controller = _controller(ble: _Ble.connected(), hfp: _Hfp());
      await controller.initializeDeviceConnectionPreferences();
      expect(controller.requiresHomiMicrophoneConfirmation(microphone), isTrue);
      expect((await controller.connectHfpDevice(microphone)).succeeded, isTrue);
      expect(controller.usesHfpInput, isTrue);
      expect(controller.h20ConnectionState().hfpReady, isTrue);
      expect(controller.isH20Ready, isFalse);
      expect(controller.lastConnectedMicrophone?.bleDeviceId, isNull);
      await controller.connectHfpDevice(
        microphone,
        confirmHomiAssociation: true,
      );
      expect(controller.isH20Ready, isTrue);
      controller.dispose();
      final restored = _controller(ble: _Ble.connected(), hfp: _Hfp());
      await restored.initializeDeviceConnectionPreferences();
      expect(restored.requiresHomiMicrophoneConfirmation(microphone), isFalse);
      await restored.connectHfpDevice(microphone);
      expect(restored.isH20Ready, isTrue);
      restored.dispose();
    },
  );

  test(
    'generic microphone remains usable and cannot be associated with HOMI',
    () async {
      final controller = _controller(ble: _Ble.connected(), hfp: _Hfp());
      const unrelated = HfpAudioDevice(
        id: 'airpods',
        name: 'AirPods',
        isConnected: true,
      );
      await controller.connectHfpDevice(
        unrelated,
        confirmHomiAssociation: true,
      );
      expect(controller.usesHfpInput, isTrue);
      expect(controller.isH20Ready, isFalse);
      expect(controller.lastConnectedMicrophone?.id, 'airpods');
      expect(controller.lastConnectedMicrophone?.bleDeviceId, isNull);
      expect(await controller.autoConnectH20Hfp(), isFalse);
      expect(controller.hfpAudioStatus.deviceId, 'airpods');
      controller.dispose();
    },
  );

  test(
    'explicit mic deselection survives controller recreation until Retry',
    () async {
      final controller = _controller(hfp: _Hfp());
      await controller.connectHfpDevice(microphone);
      await controller.disconnectHfpDevice();
      expect(controller.automaticHfpSelectionAllowed, isFalse);
      controller.dispose();
      final restoredHfp = _Hfp(devices: [microphone]);
      final restored = _controller(hfp: restoredHfp);
      await restored.initializeDeviceConnectionPreferences();
      expect(await restored.autoConnectH20Hfp(), isFalse);
      expect(restoredHfp.findCount, 0);
      await restored.resumeAutomaticDeviceConnection();
      expect(await restored.autoConnectH20Hfp(), isTrue);
      expect(restoredHfp.findCount, 1);
      restored.dispose();
    },
  );

  test(
    'explicit BLE disconnect persists and explicit connection reverses opt-out',
    () async {
      final controller = _controller(ble: _Ble.connected());
      await controller.disconnectAiv0Device();
      controller.dispose();
      final restored = _controller(ble: _Ble());
      await restored.initializeDeviceConnectionPreferences();
      expect(restored.automaticBleConnectionAllowed, isFalse);
      expect((await restored.connectAiv0Device(bleDevice)).succeeded, isTrue);
      expect(restored.automaticBleConnectionAllowed, isTrue);
      restored.dispose();
    },
  );

  test(
    'manual discovery locks immediately and cancellation drops late results',
    () async {
      final discovery = Completer<List<HfpAudioDevice>>();
      final hfp = _Hfp(discovery: discovery);
      final controller = _controller(hfp: hfp);
      final first = controller.findHfpDevices();
      final firstExpectation = expectLater(first, throwsA(isA<Exception>()));
      expect(controller.isDeviceConnectionBusy, isTrue);
      await expectLater(
        controller.findHfpDevices(),
        throwsA(isA<DeviceConnectionBusyException>()),
      );
      await controller.cancelManualDeviceConnection();
      expect(controller.automaticHfpSelectionAllowed, isTrue);
      discovery.complete([microphone]);
      await firstExpectation;
      expect(hfp.connectCount, 0);
      expect(controller.lastConnectedMicrophone, isNull);
      controller.dispose();
    },
  );

  test(
    'cancel during connection cannot select mic or overwrite saved history',
    () async {
      final connection = Completer<void>();
      final hfp = _Hfp(connection: connection);
      final controller = _controller(hfp: hfp);
      final attempt = controller.connectHfpDevice(microphone);
      await Future<void>.delayed(Duration.zero);
      await controller.cancelManualDeviceConnection();
      connection.complete();
      expect((await attempt).outcome, DeviceConnectionOutcome.cancelled);
      expect(controller.usesHfpInput, isFalse);
      expect(controller.lastConnectedMicrophone, isNull);
      expect(controller.automaticHfpSelectionAllowed, isTrue);
      controller.dispose();
    },
  );

  test(
    'auto-selection uses the saved confirmed ID among identical microphones',
    () async {
      final history = DeviceConnectionHistoryStore();
      await history.saveMicrophone(
        ConnectionDeviceRecord(
          id: 'second',
          name: 'HM-D001',
          transport: ConnectionDeviceTransport.hfp,
          connectedAt: DateTime.utc(2026, 10, 19),
          bleDeviceId: 'ble',
        ),
      );
      final hfp = _Hfp(
        devices: const [
          HfpAudioDevice(id: 'first', name: 'HM-D001', isConnected: true),
          HfpAudioDevice(id: 'second', name: 'HM-D001', isConnected: true),
        ],
      );
      final controller = _controller(ble: _Ble.connected(), hfp: hfp);
      expect(await controller.autoConnectH20Hfp(), isTrue);
      expect(controller.hfpAudioStatus.deviceId, 'second');
      expect(controller.isH20Ready, isTrue);
      controller.dispose();
    },
  );

  test(
    'explicit Retry can replace an unrelated mic while background retries cannot',
    () async {
      const unrelated = HfpAudioDevice(
        id: 'airpods',
        name: 'AirPods',
        isConnected: true,
      );
      final hfp = _Hfp(devices: [microphone]);
      final controller = _controller(ble: _Ble.connected(), hfp: hfp);
      await controller.connectHfpDevice(unrelated);
      expect(await controller.autoConnectH20Hfp(), isFalse);
      expect(hfp.status.deviceId, 'airpods');
      await controller.resumeAutomaticDeviceConnection();
      expect(await controller.autoConnectH20Hfp(), isTrue);
      expect(hfp.status.deviceId, 'mic');
      expect(controller.isH20Ready, isFalse);
      controller.dispose();
    },
  );

  test(
    'saved confirmed microphone stays identifiable when its name is unavailable',
    () async {
      final history = DeviceConnectionHistoryStore();
      await history.saveMicrophone(
        ConnectionDeviceRecord(
          id: 'known-mic',
          name: 'HM-D001',
          transport: ConnectionDeviceTransport.hfp,
          connectedAt: DateTime.utc(2026, 10, 19),
          bleDeviceId: 'ble',
        ),
      );
      final hfp = _Hfp(
        devices: const [
          HfpAudioDevice(id: 'unrelated', name: '', isConnected: true),
          HfpAudioDevice(id: 'known-mic', name: '', isConnected: true),
        ],
      );
      final controller = _controller(ble: _Ble.connected(), hfp: hfp);
      expect(await controller.autoConnectH20Hfp(), isTrue);
      expect(controller.hfpAudioStatus.deviceId, 'known-mic');
      expect(controller.isH20Ready, isTrue);
      expect(controller.lastConnectedMicrophone?.name, isEmpty);
      expect(controller.lastConnectedMicrophone?.bleDeviceId, 'ble');
      controller.dispose();
    },
  );

  test('a stored association cannot identify a different BLE device', () async {
    final history = DeviceConnectionHistoryStore();
    await history.saveMicrophone(
      ConnectionDeviceRecord(
        id: 'mic',
        name: 'HM-D001',
        transport: ConnectionDeviceTransport.hfp,
        connectedAt: DateTime.utc(2026, 10, 19),
        bleDeviceId: 'other-ble',
      ),
    );
    final controller = _controller(ble: _Ble.connected(), hfp: _Hfp());
    await controller.connectHfpDevice(microphone);
    expect(controller.isH20Ready, isFalse);
    expect(controller.lastConnectedMicrophone?.bleDeviceId, isNull);
    controller.dispose();
  });

  test(
    'cleared BLE identity keeps verified audio but a different mic does not',
    () async {
      final ble = _Ble.connected();
      final hfp = _Hfp();
      final controller = _controller(ble: ble, hfp: hfp);
      await controller.connectHfpDevice(
        microphone,
        confirmHomiAssociation: true,
      );
      expect(controller.isH20Ready, isTrue);

      ble.status = const Aiv0BleStatus(
        phase: Aiv0BlePhase.reconnecting,
        protocolConfirmed: true,
      );
      expect(controller.isH20Ready, isFalse);
      expect(controller.isHomiAudioReady, isTrue);
      expect(controller.usesHfpInput, isTrue);
      expect(controller.verifiedHomiBleDeviceId, 'ble');

      ble.status = const Aiv0BleStatus(
        phase: Aiv0BlePhase.error,
        protocolConfirmed: true,
        deviceId: 'failed-other-ble',
      );
      expect(controller.isHomiAudioReady, isTrue);
      expect(controller.verifiedHomiBleDeviceId, 'ble');

      hfp.status = const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: 'unrelated',
        deviceName: 'HM-D001',
      );
      expect(controller.isHomiAudioReady, isFalse);
      expect(controller.verifiedHomiBleDeviceId, isNull);
      controller.dispose();
    },
  );

  test(
    'saved association survives mic reconnect before BLE and rejects another HOMI',
    () async {
      final first = _controller(ble: _Ble.connected(), hfp: _Hfp());
      await first.connectHfpDevice(microphone, confirmHomiAssociation: true);
      first.dispose();

      final ble = _Ble();
      final restored = _controller(ble: ble, hfp: _Hfp());
      await restored.connectHfpDevice(microphone);
      expect(restored.isHomiAudioReady, isTrue);
      expect(restored.isH20Ready, isFalse);
      expect(restored.lastConnectedMicrophone?.bleDeviceId, 'ble');

      ble.status = const Aiv0BleStatus(
        phase: Aiv0BlePhase.connected,
        protocolConfirmed: true,
        deviceId: 'different-homi',
      );
      expect(restored.isHomiAudioReady, isFalse);
      expect(restored.isH20Ready, isFalse);
      expect(restored.verifiedHomiBleDeviceId, isNull);
      restored.dispose();
    },
  );

  test(
    'explicit MAIN disconnect keeps mic and preserves retry opt-out',
    () async {
      final controller = _controller(ble: _Ble.connected(), hfp: _Hfp());
      await controller.connectHfpDevice(
        microphone,
        confirmHomiAssociation: true,
      );
      await controller.disconnectAiv0Device();
      expect(controller.isHomiAudioReady, isTrue);
      expect(controller.isH20Ready, isFalse);
      expect(controller.automaticBleConnectionAllowed, isFalse);
      await controller.disconnectHfpDevice();
      expect(controller.isHomiAudioReady, isFalse);
      expect(controller.usesHfpInput, isFalse);
      expect(controller.automaticHfpSelectionAllowed, isFalse);
      controller.dispose();
    },
  );
}

ConversationController _controller({_Ble? ble, _Hfp? hfp}) =>
    ConversationController(
      audioInput: _Input(),
      playbackService: _Playback(),
      repository: _Repository(),
      childAge: 6,
      aiv0BleControl: ble,
      hfpAudioControl: hfp,
    );

class _Input implements AudioInput {
  @override
  bool get isAvailable => true;
  @override
  bool get isBluetooth => false;
  @override
  String get label => 'Phone';
  @override
  Stream<double> get amplitudeDbfs => const Stream.empty();
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Playback implements AudioPlaybackService {
  @override
  Stream<bool> get playingStream => const Stream.empty();
  Stream<void> get completionStream => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements ConversationRepository {
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Hfp implements HfpAudioControl, HfpConnectionAttemptControl {
  _Hfp({this.devices = const [], this.discovery, this.connection});
  final List<HfpAudioDevice> devices;
  final Completer<List<HfpAudioDevice>>? discovery;
  final Completer<void>? connection;
  int findCount = 0;
  int connectCount = 0;
  @override
  BluetoothAudioStatus status = const BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.idle,
  );
  @override
  bool get usesBrowserAudioInput => false;
  @override
  Stream<BluetoothAudioStatus> get statusChanges => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<List<HfpAudioDevice>> findDevices() async {
    findCount++;
    return discovery == null ? devices : await discovery!.future;
  }

  @override
  Future<void> connect(HfpAudioDevice device) async {
    connectCount++;
    if (connection != null) await connection!.future;
    status = BluetoothAudioStatus(
      phase: BluetoothAudioConnectionPhase.ready,
      deviceId: device.id,
      deviceName: device.name,
    );
  }

  @override
  Future<void> disconnect() async {
    status = const BluetoothAudioStatus(
      phase: BluetoothAudioConnectionPhase.idle,
    );
  }

  @override
  Future<void> cancelConnectionAttempt() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ble implements Aiv0BleControl {
  _Ble({this.connects = true});
  _Ble.connected() : connects = true {
    status = const Aiv0BleStatus(
      phase: Aiv0BlePhase.connected,
      protocolConfirmed: true,
      deviceId: 'ble',
      deviceName: 'HOMI',
    );
  }
  final bool connects;
  int connectCount = 0;
  @override
  Aiv0BleStatus status = const Aiv0BleStatus(
    phase: Aiv0BlePhase.idle,
    protocolConfirmed: false,
  );
  @override
  Stream<Aiv0BleStatus> get statusStream => const Stream.empty();
  @override
  Stream<Aiv0ButtonEvent> get buttonEvents => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> connect(String deviceId) async {
    connectCount++;
    if (connects) {
      status = Aiv0BleStatus(
        phase: Aiv0BlePhase.connected,
        protocolConfirmed: true,
        deviceId: deviceId,
        deviceName: 'HOMI',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    status = const Aiv0BleStatus(
      phase: Aiv0BlePhase.idle,
      protocolConfirmed: false,
    );
  }

  @override
  Future<void> sendAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence = 0,
  }) async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
