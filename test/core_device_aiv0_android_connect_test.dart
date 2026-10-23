import 'dart:async';

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

  test('paired Classic address is never assumed to expose BLE MAIN', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'initialize' => {'phase': 'idle'},
            'requestPermissions' || 'requestDualModeBond' => true,
            'scan' => <Object?>[],
            'scanClassic' => [
              {'id': 'AA:BB:CC:DD:EE:FF', 'name': 'HM-D001', 'rssi': -40},
            ],
            'connect' => {
              'phase': 'connected',
              'deviceId': 'AA:BB:CC:DD:EE:FF',
            },
            _ => null,
          };
        });
    final control = MethodChannelAiv0BleControl(
      enabled: true,
      draftProtocolConfirmed: false,
    );
    addTearDown(control.dispose);
    expect(await control.autoConnectKnownOrNearby(requestBond: true), isFalse);
    expect(calls.where((m) => m == 'scan'), hasLength(2));
    expect(calls, isNot(contains('connect')));
    expect(control.status.isConnected, isFalse);
    expect(control.status.message, contains('MAIN'));
    expect(
      (await SharedPreferences.getInstance()).getString(
        'aiv0_ble_last_device_id',
      ),
      isNull,
    );
  });

  for (final explicit in [true, false]) {
    test(
      'Classic-only first discovery is used only by explicit pairing=$explicit',
      () async {
        final calls = <String>[];
        final connectedIds = <String>[];
        var paired = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call.method);
              if (call.method == 'requestDualModeBond') {
                paired = true;
                return true;
              }
              if (call.method == 'connect') {
                connectedIds.add((call.arguments as Map)['deviceId'] as String);
              }
              return switch (call.method) {
                'initialize' => {'phase': 'idle'},
                'requestPermissions' => true,
                'scan' when paired => [
                  {
                    'id': 'BB:CC:DD:EE:FF:01',
                    'name': '',
                    'rssi': -35,
                    'advertisesControlService': true,
                  },
                ],
                'scan' => [
                  {'id': '11:22:33:44:55:66', 'name': '', 'rssi': -20},
                ],
                'scanClassic' => [
                  {'id': 'AA:BB:CC:DD:EE:FF', 'name': 'HM-D001', 'rssi': -40},
                ],
                'connect' => {
                  'phase': 'connected',
                  'deviceId': 'BB:CC:DD:EE:FF:01',
                  'deviceName': 'HM-D001',
                },
                _ => null,
              };
            });
        final control = MethodChannelAiv0BleControl(
          enabled: true,
          draftProtocolConfirmed: false,
        );
        addTearDown(control.dispose);

        expect(
          await control.autoConnectKnownOrNearby(requestBond: explicit),
          explicit,
        );
        if (explicit) {
          expect(
            calls,
            containsAllInOrder([
              'scan',
              'scanClassic',
              'requestDualModeBond',
              'scan',
              'connect',
            ]),
          );
          expect(control.status.isConnected, isTrue);
          expect(connectedIds, ['BB:CC:DD:EE:FF:01']);
          expect(
            (await SharedPreferences.getInstance()).getString(
              'aiv0_ble_last_device_id',
            ),
            'BB:CC:DD:EE:FF:01',
          );
        } else {
          expect(calls, isNot(contains('scanClassic')));
          expect(calls, isNot(contains('requestDualModeBond')));
        }
      },
    );
  }

  test(
    'cancelled Classic discovery cannot pair or connect after its late result',
    () async {
      final discovery = Completer<List<Map<String, Object?>>>();
      final started = Completer<void>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'initialize':
              case 'cancelConnectionAttempt':
                return {'phase': 'idle'};
              case 'requestPermissions':
                return true;
              case 'scan':
                return <Object?>[];
              case 'scanClassic':
                started.complete();
                return discovery.future;
              default:
                return null;
            }
          });
      final control = MethodChannelAiv0BleControl(
        enabled: true,
        draftProtocolConfirmed: false,
      );
      addTearDown(control.dispose);
      final connection = control.autoConnectKnownOrNearby(requestBond: true);
      await started.future;
      await control.cancelConnectionAttempt();
      expect(await connection, isFalse);
      discovery.complete([
        {'id': 'AA:BB:CC:DD:EE:FF', 'name': 'HM-D001', 'rssi': -40},
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(calls, isNot(contains('requestDualModeBond')));
      expect(calls, isNot(contains('connect')));
    },
  );

  for (final savedName in <String?>[null, 'HM-D001', 'HM-D001']) {
    test('radio turns off during auto-connect with saved=$savedName', () async {
      if (savedName != null) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'aiv0_ble_last_device_id': 'AA:BB:CC:DD:EE:FF',
          'aiv0_ble_last_device_name': savedName,
        });
      }
      final calls = <String>[];
      final logs = <String?>[];
      final previousPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message);
      addTearDown(() => debugPrint = previousPrint);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return switch (call.method) {
              'initialize' => <String, Object?>{'phase': 'idle'},
              'requestPermissions' => true,
              'scan' ||
              'connect' => throw PlatformException(code: 'BLUETOOTH_DISABLED'),
              _ => null,
            };
          });
      final control = MethodChannelAiv0BleControl(
        enabled: true,
        draftProtocolConfirmed: false,
      );
      addTearDown(control.dispose);
      expect(await control.autoConnectKnownOrNearby(), isFalse);
      expect(
        calls.where((m) => m == 'scan').length,
        savedName == 'HM-D001' ? 0 : 1,
      );
      expect(
        calls.where((m) => m == 'connect').length,
        savedName == 'HM-D001' ? 1 : 0,
      );
      expect(
        logs.where((m) => m?.contains('BLUETOOTH_DISABLED') == true),
        isEmpty,
      );
    });
  }

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
