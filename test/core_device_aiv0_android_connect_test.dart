import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ailingo_aiv0_ble_control');
  const events = MethodChannel('ailingo_aiv0_ble_control/events');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'auto-connect accepts native BLE success before status event arrives',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'aiv0_ble_last_device_id': 'AA:BB:CC:DD:EE:FF',
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'initialize':
                return <Object?, Object?>{'phase': 'idle'};
              case 'requestPermissions':
                return true;
              case 'connect':
                return <Object?, Object?>{
                  'phase': 'connected',
                  'deviceId': 'AA:BB:CC:DD:EE:FF',
                  'deviceName': 'HM-D001',
                  'mainNotificationState': 'notifying',
                };
              default:
                return null;
            }
          });
      final control = MethodChannelAiv0BleControl(
        enabled: true,
        draftProtocolConfirmed: false,
      );

      expect(await control.autoConnectKnownOrNearby(), isTrue);

      expect(control.status.isConnected, isTrue);
      expect(control.status.deviceName, 'HM-D001');
      expect(control.status.mainNotificationState, 'notifying');
      await control.dispose();
    },
  );

  test(
    'connected Classic HM-D001 takes priority over a stale BLE address',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'aiv0_ble_last_device_id': 'AA:AA',
        'aiv0_ble_last_device_name': 'HM-D001',
      });
      final connectedIds = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'initialize':
                return <Object?, Object?>{'phase': 'idle'};
              case 'requestPermissions':
                return true;
              case 'scan':
                return <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'AA:AA',
                    'name': 'HM-D001',
                    'rssi': -30,
                  },
                  <String, Object?>{
                    'id': 'BB:BB',
                    'name': 'HM-D001',
                    'rssi': -80,
                  },
                ];
              case 'connect':
                final id = (call.arguments as Map<Object?, Object?>)['deviceId']
                    .toString();
                connectedIds.add(id);
                return <Object?, Object?>{
                  'phase': 'connected',
                  'deviceId': id,
                  'deviceName': 'HM-D001',
                  'mainNotificationState': 'notifying',
                };
              default:
                return null;
            }
          });
      final control = MethodChannelAiv0BleControl(
        enabled: true,
        draftProtocolConfirmed: false,
      );

      expect(
        await control.autoConnectKnownOrNearby(
          connectedHfpDeviceIds: const <String>['BB:BB'],
        ),
        isTrue,
      );
      expect(connectedIds, <String>['BB:BB']);
      await control.dispose();
    },
  );
}
