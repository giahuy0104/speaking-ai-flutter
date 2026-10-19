import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/h20_connection_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'BLE remains a partial connection when system pairing is rejected',
    () async {
      final bridge = _ConnectionBridge(bondAccepted: false);
      addTearDown(bridge.dispose);

      final mainConnected = await bridge.control.autoConnectKnownOrNearby(
        requestBond: true,
      );

      expect(
        bridge.methods,
        containsAllInOrder(['requestDualModeBond', 'connect']),
      );
      expect(mainConnected, isTrue);
      expect(bridge.control.status.isConnected, isTrue);
      // The native boundary reports GATT readiness only. A UI must not convert
      // this success to complete HOMI readiness or promise a paired HFP device.
      final state = H20ConnectionState.from(
        bleStatus: bridge.control.status,
        hfpStatus: const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.idle,
        ),
        hfpInputSelected: false,
      );
      expect(state.bleReady, isTrue);
      expect(state.isHomiAudioReady, isFalse);
      expect(state.isH20Ready, isFalse);
      expect(state.canStartStrictHfpTurn, isFalse);
    },
  );

  test(
    'the advanced BLE-only connect does not pair the OS audio profile',
    () async {
      final bridge = _ConnectionBridge(bondAccepted: true);
      addTearDown(bridge.dispose);

      await bridge.control.connect(_ConnectionBridge.deviceId);

      expect(bridge.control.status.isConnected, isTrue);
      expect(
        bridge.methods.where((method) => method == 'connect'),
        hasLength(1),
      );
      expect(bridge.methods, isNot(contains('requestDualModeBond')));
      expect(bridge.methods, isNot(contains('scan')));
    },
  );

  test('explicit pairing reuses the verified MAIN connection', () async {
    final bridge = _ConnectionBridge(bondAccepted: true);
    addTearDown(bridge.dispose);
    await bridge.control.connect(_ConnectionBridge.deviceId);
    bridge.methods.clear();

    expect(
      await bridge.control.requestSystemPairingForConnectedDevice(),
      isTrue,
    );
    expect(bridge.methods, ['requestPermissions', 'requestDualModeBond']);
    expect(bridge.pairingDeviceIds, [_ConnectionBridge.deviceId]);
    expect(bridge.control.status.isConnected, isTrue);
  });

  for (final platformError in [false, true]) {
    test(
      'explicit pairing returns false on ${platformError ? 'native error' : 'rejection'}',
      () async {
        final bridge = _ConnectionBridge(bondAccepted: false);
        addTearDown(bridge.dispose);
        await bridge.control.connect(_ConnectionBridge.deviceId);
        if (platformError) {
          bridge.failures['requestDualModeBond'] = PlatformException(
            code: 'BOND_FAILED',
          );
        }
        bridge.methods.clear();

        expect(
          await bridge.control.requestSystemPairingForConnectedDevice(),
          isFalse,
        );
        expect(bridge.methods, ['requestPermissions', 'requestDualModeBond']);
        expect(bridge.control.status.isConnected, isTrue);
      },
    );
  }

  test(
    'cancelled pairing ignores a later OS acceptance and retains MAIN',
    () async {
      final accepted = Completer<bool>();
      final bridge = _ConnectionBridge(
        bondAccepted: true,
        onBond: () => accepted.future,
      );
      addTearDown(bridge.dispose);
      await bridge.control.connect(_ConnectionBridge.deviceId);
      bridge.methods.clear();

      final pairing = bridge.control.requestSystemPairingForConnectedDevice();
      await bridge.bondStarted.future;
      await bridge.control.cancelConnectionAttempt();
      expect(await pairing, isFalse);
      accepted.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.control.status.isConnected, isTrue);
      expect(bridge.methods, [
        'requestPermissions',
        'requestDualModeBond',
        'cancelConnectionAttempt',
      ]);
    },
  );

  test('denied permission does not invoke system pairing', () async {
    final bridge = _ConnectionBridge(bondAccepted: true);
    addTearDown(bridge.dispose);
    await bridge.control.connect(_ConnectionBridge.deviceId);
    bridge.permissionGranted = false;
    bridge.methods.clear();

    expect(
      await bridge.control.requestSystemPairingForConnectedDevice(),
      isFalse,
    );
    expect(bridge.methods, ['requestPermissions']);
    expect(bridge.control.status.isConnected, isTrue);
  });

  for (final switched in [false, true]) {
    test(
      'late pairing does not accept a ${switched ? 'different' : 'lost'} MAIN connection',
      () async {
        final accepted = Completer<bool>();
        final bridge = _ConnectionBridge(
          bondAccepted: true,
          onBond: () => accepted.future,
        );
        addTearDown(bridge.dispose);
        await bridge.control.connect(_ConnectionBridge.deviceId);
        final pairing = bridge.control.requestSystemPairingForConnectedDevice();
        await bridge.bondStarted.future;
        await bridge.emitStatus(<String, Object?>{
          'phase': switched ? 'connected' : 'idle',
          if (switched) 'deviceId': '11:22:33:44:55:66',
        });
        accepted.complete(true);

        expect(await pairing, isFalse);
        expect(bridge.pairingDeviceIds, [_ConnectionBridge.deviceId]);
      },
    );
  }

  test(
    'MAIN lost during permission check is never passed to system pairing',
    () async {
      final allowed = Completer<bool>();
      final requested = Completer<void>();
      final bridge = _ConnectionBridge(bondAccepted: true);
      addTearDown(bridge.dispose);
      await bridge.control.connect(_ConnectionBridge.deviceId);
      bridge.onPermissions = () {
        requested.complete();
        return allowed.future;
      };
      final pairing = bridge.control.requestSystemPairingForConnectedDevice();
      await requested.future;
      await bridge.emitStatus(<String, Object?>{'phase': 'idle'});
      allowed.complete(true);

      expect(await pairing, isFalse);
      expect(bridge.pairingDeviceIds, isEmpty);
    },
  );

  test(
    'no connected MAIN means there is no target for system pairing',
    () async {
      final bridge = _ConnectionBridge(bondAccepted: true);
      addTearDown(bridge.dispose);

      expect(
        await bridge.control.requestSystemPairingForConnectedDevice(),
        isFalse,
      );
      expect(bridge.methods, ['initialize']);
      expect(bridge.pairingDeviceIds, isEmpty);
    },
  );

  for (final reason in ['iOS', 'disabled', 'pairing disabled']) {
    test('$reason never requests Android system pairing', () async {
      final bridge = _ConnectionBridge(
        bondAccepted: true,
        platform: reason == 'iOS' ? TargetPlatform.iOS : TargetPlatform.android,
        enabled: reason != 'disabled',
        dualModePairingEnabled: reason != 'pairing disabled',
      );
      addTearDown(bridge.dispose);
      if (reason != 'disabled') {
        await bridge.control.connect(_ConnectionBridge.deviceId);
      }
      bridge.methods.clear();

      expect(
        await bridge.control.requestSystemPairingForConnectedDevice(),
        isFalse,
      );
      expect(bridge.methods, isEmpty);
    });
  }

  for (final failingMethod in ['initialize', 'bluetoothAdapterState']) {
    test(
      '$failingMethod platform error keeps Bluetooth state unknown',
      () async {
        final bridge = _ConnectionBridge(bondAccepted: true);
        addTearDown(bridge.dispose);
        bridge.failures[failingMethod] = PlatformException(
          code: 'ADAPTER_UNAVAILABLE',
        );

        expect(
          await bridge.control.readBluetoothAdapterState(),
          Aiv0BluetoothAdapterState.unknown,
        );
      },
    );
  }
}

class _ConnectionBridge {
  _ConnectionBridge({
    required this.bondAccepted,
    this.onBond,
    TargetPlatform platform = TargetPlatform.android,
    bool enabled = true,
    bool dualModePairingEnabled = true,
  }) {
    debugDefaultTargetPlatformOverride = platform;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _messenger.setMockMethodCallHandler(_events, (_) async => null);
    _messenger.setMockMethodCallHandler(_channel, (call) async {
      methods.add(call.method);
      if (failures[call.method] case final failure?) throw failure;
      if (call.method == 'requestDualModeBond') {
        pairingDeviceIds.add((call.arguments as Map)['deviceId'] as String);
        if (!bondStarted.isCompleted) bondStarted.complete();
        return onBond?.call() ?? bondAccepted;
      }
      if (call.method == 'connect') _connected = true;
      return switch (call.method) {
        'initialize' => <Object?, Object?>{'phase': 'idle'},
        'requestPermissions' => onPermissions?.call() ?? permissionGranted,
        'scan' => <Object?>[
          <Object?, Object?>{
            'id': deviceId,
            'name': 'HM-D001',
            'rssi': -35,
            'advertisesControlService': true,
          },
        ],
        'connect' || 'cancelConnectionAttempt' => <Object?, Object?>{
          'phase': _connected ? 'connected' : 'idle',
          if (_connected) 'deviceId': deviceId,
          if (_connected) 'deviceName': 'HM-D001',
        },
        _ => null,
      };
    });
    control = MethodChannelAiv0BleControl(
      enabled: enabled,
      draftProtocolConfirmed: false,
      dualModePairingEnabled: dualModePairingEnabled,
      methodChannel: _channel,
      eventChannel: const EventChannel('bluetooth_success_contract/events'),
    );
  }

  static const deviceId = 'AA:BB:CC:DD:EE:FF';
  static const _channel = MethodChannel('bluetooth_success_contract');
  static const _events = MethodChannel('bluetooth_success_contract/events');
  final bool bondAccepted;
  final Future<bool> Function()? onBond;
  final methods = <String>[];
  final failures = <String, PlatformException>{};
  final pairingDeviceIds = <String>[];
  final bondStarted = Completer<void>();
  bool permissionGranted = true;
  Future<bool> Function()? onPermissions;
  bool _connected = false;
  final _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late final MethodChannelAiv0BleControl control;

  Future<void> emitStatus(Map<String, Object?> status) async {
    await _messenger.handlePlatformMessage(
      _events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
        'type': 'status',
        ...status,
      }),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> dispose() async {
    await control.dispose();
    _messenger.setMockMethodCallHandler(_channel, null);
    _messenger.setMockMethodCallHandler(_events, null);
    debugDefaultTargetPlatformOverride = null;
  }
}
