import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real channel adapters pass one attempt through inventory, scan, bond and GATT',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      const bleChannel = MethodChannel('ailingo_aiv0_ble_control');
      const hfpChannel = MethodChannel('ailingo_hfp_audio');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      for (final name in [
        'ailingo_aiv0_ble_control/events',
        'ailingo_hfp_audio/events',
      ]) {
        messenger.setMockMethodCallHandler(
          MethodChannel(name),
          (_) async => null,
        );
      }
      messenger.setMockMethodCallHandler(bleChannel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'initialize' => {'phase': 'idle'},
          'requestPermissions' => true,
          'scan' => [
            {
              'id': 'AA:BB:CC:DD:EE:FF',
              'name': 'HM-D001',
              'rssi': -35,
              'advertisesControlService': true,
            },
          ],
          'requestDualModeBond' => true,
          'connect' => {
            'phase': 'connected',
            'deviceId': 'AA:BB:CC:DD:EE:FF',
            'deviceName': 'HM-D001',
          },
          _ => null,
        };
      });
      messenger.setMockMethodCallHandler(hfpChannel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'findDevices' => <Object?>[],
          'requestPermissions' => true,
          _ => null,
        };
      });
      final ble = MethodChannelAiv0BleControl(
        enabled: true,
        draftProtocolConfirmed: false,
        dualModePairingEnabled: true,
      );
      final audio = MethodChannelHfpAudioControl(enabled: true);
      addTearDown(() async {
        await ble.dispose();
        await audio.dispose();
        for (final name in [
          'ailingo_aiv0_ble_control',
          'ailingo_hfp_audio',
          'ailingo_aiv0_ble_control/events',
          'ailingo_hfp_audio/events',
        ]) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
        debugDefaultTargetPlatformOverride = null;
      });
      final diagnostics = DeviceConnectionDiagnostics(
        enabled: true,
        sessionId: 'channel',
      );
      await diagnostics.run(7, () async {
        await audio.findDevices();
        expect(await ble.autoConnectKnownOrNearby(requestBond: true), isTrue);
      });
      for (final method in [
        'findDevices',
        'scan',
        'requestDualModeBond',
        'connect',
      ]) {
        final call = calls.singleWhere((c) => c.method == method);
        expect(
          (call.arguments as Map)['attemptId'],
          'channel-7',
          reason: method,
        );
      }
      // Ordinary callers outside onboarding retain the previous method contract.
      calls.clear();
      await audio.findDevices();
      expect(
        calls.singleWhere((c) => c.method == 'findDevices').arguments,
        isNull,
      );
    },
  );
}
