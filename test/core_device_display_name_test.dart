import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/innotrik_ble_audio_input.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/device_display_name.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing BLE name remains raw and is not identified as H20', () {
    final device = Aiv0BleDevice.fromMap(<Object?, Object?>{
      'id': 'unknown-ble',
      'rssi': -30,
    });
    expect(device.name, isEmpty);
    expect(device.isLikelyAiv0, isFalse);
    expect(selectAiv0AutoConnectCandidate(<Aiv0BleDevice>[device]), isNull);
    expect(
      localizedDeviceName(device.name, DisplayLanguage.vietnamese),
      'Thiết bị không xác định',
    );
    expect(
      localizedDeviceName(device.name, DisplayLanguage.simplifiedChinese),
      '未知设备',
    );
  });

  test(
    'unnamed control service device can still be selected by its service',
    () {
      final device = Aiv0BleDevice.fromMap(<Object?, Object?>{
        'id': 'control-ble',
        'advertisesControlService': true,
        'rssi': -30,
      });
      expect(selectAiv0AutoConnectCandidate(<Aiv0BleDevice>[device]), device);
      expect(device.name, isEmpty);
    },
  );

  test('unknown HFP names do not use an identifier as the friendly name', () {
    final device = HfpAudioDevice.fromJson(<String, Object>{
      'id': 'H20-looking-device-identifier',
      'isConnected': true,
    });
    expect(device.name, isEmpty);
    expect(selectLikelyH20HfpDevice(<HfpAudioDevice>[device]), isNull);
    expect(
      localizedDeviceName(
        device.name,
        DisplayLanguage.simplifiedChinese,
        deviceId: device.id,
      ),
      '未知设备',
    );
  });

  test(
    'unknown fallback follows language and preserves actual device names',
    () {
      for (final unknown in <String?>[null, '', '  ', 'AA:BB:CC:DD:EE:FF']) {
        expect(
          localizedDeviceName(
            unknown,
            DisplayLanguage.vietnamese,
            deviceId: 'AA:BB:CC:DD:EE:FF',
          ),
          'Thiết bị không xác định',
        );
      }
      for (final known in <String>['H20', 'HM-D001', 'AirPods']) {
        expect(
          localizedDeviceName(' $known ', DisplayLanguage.simplifiedChinese),
          known,
        );
      }
    },
  );

  test('an unnamed new BLE connection clears the old saved name', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aiv0_ble_last_device_id': 'old',
      'aiv0_ble_last_device_name': 'H20',
    });
    const channel = MethodChannel('test.raw-ble-name');
    const events = MethodChannel('test.raw-ble-name/events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'initialize' => <String, Object>{'phase': 'idle'},
        'requestPermissions' => true,
        'connect' => <String, Object>{
          'phase': 'connected',
          'deviceId': 'new',
          'deviceName': '',
        },
        _ => null,
      },
    );
    final control = MethodChannelAiv0BleControl(
      enabled: true,
      draftProtocolConfirmed: false,
      methodChannel: channel,
      eventChannel: const EventChannel('test.raw-ble-name/events'),
    );
    try {
      await control.connect('new');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('aiv0_ble_last_device_id'), 'new');
      expect(preferences.getString('aiv0_ble_last_device_name'), isEmpty);
    } finally {
      await control.dispose();
      messenger.setMockMethodCallHandler(events, null);
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'legacy BLE audio status never gives a new device the previous name',
    () async {
      const channel = MethodChannel('test.raw-innotrik-name');
      const events = MethodChannel('test.raw-innotrik-name/events');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(events, (_) async => null);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object>{
          'phase': 'ready',
          'deviceId': 'old',
          'deviceName': 'H20',
        },
      );
      final input = InnotrikBleAudioInput(
        enabled: true,
        controlChannel: channel,
        eventChannel: const EventChannel('test.raw-innotrik-name/events'),
      );
      try {
        await input.initializeBluetooth();
        expect(input.bluetoothStatus.deviceName, 'H20');
        for (final status in <Map<String, Object>>[
          {'phase': 'ready', 'deviceId': 'new'},
          {'phase': 'ready', 'deviceId': 'new', 'deviceName': ''},
        ]) {
          await messenger.handlePlatformMessage(
            events.name,
            const StandardMethodCodec().encodeSuccessEnvelope(status),
            (_) {},
          );
          await Future<void>.delayed(Duration.zero);
          expect(input.bluetoothStatus.deviceId, 'new');
          expect(input.bluetoothStatus.deviceName, isNull);
        }
      } finally {
        await input.dispose();
        messenger.setMockMethodCallHandler(events, null);
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
