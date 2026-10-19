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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const savedId = 'AA:BB:CC:DD:EE:01';
  const freshId = 'AA:BB:CC:DD:EE:02';
  const connected = <String, Object?>{
    'phase': 'connected',
    'deviceId': freshId,
    'deviceName': 'HM-D001',
    'mainNotificationState': 'notifying',
  };
  const freshDevice = <String, Object?>{
    'id': freshId,
    'name': 'HM-D001',
    'rssi': -40,
    'advertisesControlService': true,
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(events, (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
    debugDefaultTargetPlatformOverride = null;
  });

  MethodChannelAiv0BleControl createControl() {
    final control = MethodChannelAiv0BleControl(
      enabled: true,
      draftProtocolConfirmed: false,
    );
    addTearDown(control.dispose);
    return control;
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('$platform cancellation', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);

      test(
        'control-only recovery never scans, pairs, or selects another unit',
        () async {
          final calls = <MethodCall>[];
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'initialize' => {'phase': 'error'},
              'requestPermissions' => true,
              'connect' => throw PlatformException(code: 'CONNECT_FAILED'),
              'scan' => [freshDevice],
              _ => null,
            };
          });
          final control = createControl();
          expect(
            await control.autoConnectKnownOrNearby(onlyDeviceId: savedId),
            isFalse,
          );
          expect(
            calls.where((call) => call.method == 'connect').single.arguments,
            {'deviceId': savedId},
          );
          expect(
            calls.where(
              (call) =>
                  call.method == 'scan' || call.method == 'requestDualModeBond',
            ),
            isEmpty,
          );
        },
      );

      test(
        'control-only recovery honors cancel and ignores late connection',
        () async {
          final connecting = Completer<void>();
          final connection = Completer<Map<String, Object?>>();
          messenger.setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'initialize':
              case 'cancelConnectionAttempt':
                return {'phase': 'idle'};
              case 'requestPermissions':
                return true;
              case 'connect':
                connecting.complete();
                return connection.future;
              default:
                return null;
            }
          });
          final control = createControl();
          final attempt = control.autoConnectKnownOrNearby(
            onlyDeviceId: savedId,
          );
          await connecting.future;
          await control.cancelConnectionAttempt();
          expect(await attempt, isFalse);
          connection.complete({...connected, 'deviceId': savedId});
          await Future<void>.delayed(Duration.zero);
          expect(control.status.isConnected, isFalse);
        },
      );

      test(
        'cancel settles before permission and ignores its late approval',
        () async {
          SharedPreferences.setMockInitialValues({
            'aiv0_ble_last_device_id': savedId,
          });
          final requested = Completer<void>();
          final permission = Completer<bool>();
          final methods = <String>[];
          messenger.setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            switch (call.method) {
              case 'initialize':
              case 'cancelConnectionAttempt':
                return {'phase': 'idle'};
              case 'requestPermissions':
                requested.complete();
                return permission.future;
              default:
                return null;
            }
          });
          final control = createControl();
          final attempt = control.autoConnectKnownOrNearby();
          await requested.future;
          await control.cancelConnectionAttempt();
          expect(await attempt, isFalse);
          permission.complete(true);
          await Future<void>.delayed(Duration.zero);
          expect(methods, isNot(contains('connect')));
          expect(methods, isNot(contains('scan')));
          expect(control.status.phase, Aiv0BlePhase.idle);
        },
      );

      test(
        'retry scans afresh and ignores the cancelled scan result',
        () async {
          final scanning = Completer<void>();
          final oldScan = Completer<List<Map<String, Object?>>>();
          var scans = 0;
          final connectedIds = <String>[];
          messenger.setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'initialize':
              case 'cancelConnectionAttempt':
                return {'phase': 'idle'};
              case 'requestPermissions':
                return true;
              case 'scan':
                scans += 1;
                if (scans == 1) {
                  scanning.complete();
                  return oldScan.future;
                }
                return [freshDevice];
              case 'connect':
                connectedIds.add((call.arguments as Map)['deviceId'] as String);
                return connected;
              default:
                return null;
            }
          });
          final control = createControl();
          final oldAttempt = control.autoConnectKnownOrNearby();
          await scanning.future;
          expect(await control.retryKnownOrNearby(), isTrue);
          expect(await oldAttempt, isFalse);
          oldScan.complete([
            {...freshDevice, 'id': savedId},
          ]);
          await Future<void>.delayed(Duration.zero);
          expect(scans, 2);
          expect(connectedIds, [freshId]);
          expect(control.status.deviceId, freshId);
        },
      );

      test(
        'cancel ignores late native connect completion and persistence',
        () async {
          SharedPreferences.setMockInitialValues({
            'aiv0_ble_last_device_id': savedId,
          });
          final connecting = Completer<void>();
          final connection = Completer<Map<String, Object?>>();
          var scans = 0;
          messenger.setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'initialize':
              case 'cancelConnectionAttempt':
                return {'phase': 'idle'};
              case 'requestPermissions':
                return true;
              case 'connect':
                connecting.complete();
                return connection.future;
              case 'scan':
                scans += 1;
                return [];
              default:
                return null;
            }
          });
          final control = createControl();
          final attempt = control.autoConnectKnownOrNearby();
          await connecting.future;
          await control.cancelConnectionAttempt();
          expect(await attempt, isFalse);
          connection.complete(connected);
          await Future<void>.delayed(Duration.zero);
          expect(control.status.phase, Aiv0BlePhase.idle);
          expect(scans, 0);
          final preferences = await SharedPreferences.getInstance();
          expect(preferences.getString('aiv0_ble_last_device_name'), isNull);
        },
      );

      test(
        'cancel preserves verified BLE while HFP retry is separate',
        () async {
          final methods = <String>[];
          messenger.setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            return switch (call.method) {
              'initialize' || 'cancelConnectionAttempt' => connected,
              _ => null,
            };
          });
          final control = createControl();
          await control.initialize();
          await control.cancelConnectionAttempt();
          expect(control.status.isConnected, isTrue);
          expect(await control.retryKnownOrNearby(), isTrue);
          expect(methods, isNot(contains('connect')));
          expect(methods, isNot(contains('scan')));
        },
      );

      test(
        'explicit retry clears manual optout and skips saved ID fastpath',
        () async {
          SharedPreferences.setMockInitialValues({
            'aiv0_ble_last_device_id': savedId,
          });
          final methods = <String>[];
          messenger.setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            return switch (call.method) {
              'initialize' || 'cancelConnectionAttempt' => {'phase': 'idle'},
              'requestPermissions' => true,
              'scan' => [freshDevice],
              'connect' => connected,
              _ => null,
            };
          });
          final control = createControl();
          await control.disconnect();
          expect(await control.autoConnectKnownOrNearby(), isFalse);
          expect(await control.retryKnownOrNearby(), isTrue);
          expect(methods.indexOf('scan'), lessThan(methods.indexOf('connect')));
        },
      );
    });
  }

  test(
    'Android cancel stops continuation after system pairing finishes late',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final bonding = Completer<void>();
      final bond = Completer<bool>();
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        switch (call.method) {
          case 'initialize':
          case 'cancelConnectionAttempt':
            return {'phase': 'idle'};
          case 'requestPermissions':
            return true;
          case 'scan':
            return [freshDevice];
          case 'requestDualModeBond':
            bonding.complete();
            return bond.future;
          default:
            return null;
        }
      });
      final control = createControl();
      final attempt = control.autoConnectKnownOrNearby(requestBond: true);
      await bonding.future;
      await control.cancelConnectionAttempt();
      expect(await attempt, isFalse);
      bond.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(methods, isNot(contains('connect')));
    },
  );

  test(
    'manual disconnect during permission prevents continuation and retry',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final requested = Completer<void>();
      final permission = Completer<bool>();
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        switch (call.method) {
          case 'initialize':
            return {'phase': 'idle'};
          case 'requestPermissions':
            requested.complete();
            return permission.future;
          default:
            return null;
        }
      });
      final control = createControl();
      final attempt = control.autoConnectKnownOrNearby();
      await requested.future;
      await control.disconnect();
      expect(await attempt, isFalse);
      permission.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(await control.autoConnectKnownOrNearby(), isFalse);
      expect(methods, isNot(contains('scan')));
      expect(methods, isNot(contains('connect')));
    },
  );
}
