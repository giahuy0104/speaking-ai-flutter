import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/h20_connection_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hfpReady = BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.ready,
    deviceId: 'h20-hfp',
    routeActive: true,
  );
  const hfpReadyIdle = BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.ready,
    deviceId: 'h20-hfp',
    deviceName: 'H20',
  );
  const hfpMissing = BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.idle,
  );
  const hfpSelectedButIdle = BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.idle,
    deviceId: 'h20-hfp',
    deviceName: 'H20',
  );
  const bleReady = Aiv0BleStatus(
    phase: Aiv0BlePhase.connected,
    deviceId: 'h20-hfp',
    protocolConfirmed: false,
  );
  const bleMissing = Aiv0BleStatus(
    phase: Aiv0BlePhase.idle,
    protocolConfirmed: false,
  );

  test('unrelated microphone remains usable without making HOMI ready', () {
    final state = H20ConnectionState.from(
      hfpStatus: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: 'airpods',
        deviceName: 'AirPods Pro',
      ),
      bleStatus: bleReady,
    );
    expect(state.hfpReady, isTrue);
    expect(state.hfpMatchesHomi, isFalse);
    expect(state.isH20Ready, isFalse);
    expect(state.canStartStrictHfpTurn, isFalse);
  });

  test('same advertised name is not proof of a physical association', () {
    final state = H20ConnectionState.from(
      hfpStatus: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: 'hfp-uuid',
        deviceName: 'H20',
      ),
      bleStatus: const Aiv0BleStatus(
        phase: Aiv0BlePhase.connected,
        protocolConfirmed: true,
        deviceId: 'ble-uuid',
        deviceName: 'H20',
      ),
    );
    expect(state.hfpReady, isTrue);
    expect(state.isH20Ready, isFalse);
  });

  test(
    'an explicitly confirmed association supports separate platform IDs',
    () {
      final state = H20ConnectionState.from(
        hfpStatus: hfpReadyIdle,
        bleStatus: const Aiv0BleStatus(
          phase: Aiv0BlePhase.connected,
          protocolConfirmed: true,
          deviceId: 'ble-uuid',
        ),
        hfpMatchesHomi: true,
      );
      expect(state.isH20Ready, isTrue);
    },
  );

  test('normalizes MAC formatting without collapsing unrelated opaque IDs', () {
    expect(sameConnectionDeviceId('AA:BB:CC:DD:EE:FF', 'aabbccddeeff'), isTrue);
    expect(sameConnectionDeviceId('id-a', 'ida'), isFalse);
    expect(sameConnectionDeviceId('', ''), isFalse);
  });

  test('requires both transports before reporting H20 ready', () {
    expect(
      H20ConnectionState.from(hfpStatus: hfpReady, bleStatus: bleMissing).phase,
      H20ConnectionPhase.hfpReady,
    );
    expect(
      H20ConnectionState.from(hfpStatus: hfpMissing, bleStatus: bleReady).phase,
      H20ConnectionPhase.bleReady,
    );
    expect(
      H20ConnectionState.from(hfpStatus: hfpReady, bleStatus: bleReady).phase,
      H20ConnectionPhase.h20Ready,
    );
  });

  test(
    'verified HFP audio survives MAIN loss without claiming full readiness',
    () {
      final state = H20ConnectionState.from(
        hfpStatus: hfpReadyIdle,
        bleStatus: bleMissing,
        hfpMatchesHomi: true,
      );
      expect(state.isHomiAudioReady, isTrue);
      expect(state.isH20Ready, isFalse);
      expect(state.canStartStrictHfpTurn, isFalse);
      expect(
        H20ConnectionState.from(
          hfpStatus: hfpSelectedButIdle,
          bleStatus: bleMissing,
          hfpMatchesHomi: true,
        ).isHomiAudioReady,
        isFalse,
      );
    },
  );

  test('keeps HFP ownership visible while a MAIN turn is active', () {
    final state = H20ConnectionState.from(
      hfpStatus: hfpReady,
      bleStatus: bleMissing,
      mainTurnActive: true,
    );

    expect(state.phase, H20ConnectionPhase.mainTurnActive);
    expect(state.hfpReady, isTrue);
    expect(state.bleReady, isFalse);
  });

  test('allows MAIN to activate a selected but currently idle HFP route', () {
    final state = H20ConnectionState.from(
      hfpStatus: hfpReadyIdle,
      bleStatus: bleReady,
    );

    expect(state.phase, H20ConnectionPhase.h20Ready);
    expect(state.hfpSelected, isTrue);
    expect(state.hfpReady, isTrue);
    expect(state.routeActive, isFalse);
    expect(state.canStartStrictHfpTurn, isTrue);
  });

  test('does not treat a remembered but disconnected HFP device as ready', () {
    final state = H20ConnectionState.from(
      hfpStatus: hfpSelectedButIdle,
      bleStatus: bleReady,
    );

    expect(state.phase, H20ConnectionPhase.bleReady);
    expect(state.hfpSelected, isTrue);
    expect(state.hfpReady, isFalse);
    expect(state.canStartStrictHfpTurn, isFalse);
  });

  test('does not start strict HFP turn without a selected HFP input', () {
    final state = H20ConnectionState.from(
      hfpStatus: hfpMissing,
      bleStatus: bleReady,
    );

    expect(state.hfpSelected, isFalse);
    expect(state.canStartStrictHfpTurn, isFalse);
  });

  test('does not report ready until the app selects H20 as its input', () {
    final state = H20ConnectionState.from(
      hfpStatus: hfpReadyIdle,
      bleStatus: bleReady,
      hfpInputSelected: false,
    );

    expect(state.hfpSelected, isFalse);
    expect(state.isH20Ready, isFalse);
    expect(state.canStartStrictHfpTurn, isFalse);
  });
}
