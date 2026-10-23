import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = HfpAudioDevice(id: 'new', name: 'HM-D001', isConnected: true);
  const oldStatus = <String, dynamic>{
    'phase': 'ready',
    'deviceId': 'old',
    'deviceName': 'HOMI',
  };

  test('cancel during permission prevents native connect dispatch', () async {
    final permission = Completer<bool>();
    final calls = <String>[];
    final control = _control('permission', (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'initialize' => oldStatus,
        'requestPermissions' => permission.future,
        _ => null,
      };
    });
    final pending = control.connect(device);
    final expectation = expectLater(pending, throwsA(isA<HfpAudioException>()));
    await _flush();
    await control.cancelConnectionAttempt();
    permission.complete(true);
    await expectation;
    expect(calls, isNot(contains('connect')));
    expect(calls, isNot(contains('disconnect')));
    expect(control.status.deviceId, 'old');
  });

  test(
    'cancel discovery invokes native cancellation and ignores late results',
    () async {
      final discovery = Completer<List<Map<String, dynamic>>>();
      final calls = <String>[];
      final control = _control('discovery', (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'initialize' => oldStatus,
          'requestPermissions' => true,
          'findDevices' => discovery.future,
          'cancelConnectionAttempt' => oldStatus,
          _ => null,
        };
      });
      final pending = control.findDevices();
      final expectation = expectLater(
        pending,
        throwsA(isA<HfpAudioException>()),
      );
      await _flush();
      await control.cancelConnectionAttempt();
      discovery.complete([
        {'id': 'new', 'name': 'HM-D001', 'isConnected': true},
      ]);
      await expectation;
      expect(calls, contains('cancelConnectionAttempt'));
      expect(calls, isNot(contains('disconnect')));
      expect(control.status.deviceId, 'old');
    },
  );

  test(
    'cancelled connect snapshot cannot overwrite the restored selection',
    () async {
      final connection = Completer<Map<String, dynamic>>();
      final control = _control(
        'connect',
        (call) async => switch (call.method) {
          'initialize' => oldStatus,
          'requestPermissions' => true,
          'connect' => connection.future,
          'cancelConnectionAttempt' => oldStatus,
          _ => null,
        },
      );
      final pending = control.connect(device);
      final expectation = expectLater(
        pending,
        throwsA(isA<HfpAudioException>()),
      );
      await _flush();
      await control.cancelConnectionAttempt();
      connection.complete({
        'phase': 'ready',
        'deviceId': 'new',
        'deviceName': 'HM-D001',
      });
      await expectation;
      expect(control.status.deviceId, 'old');
      expect(control.status.deviceName, 'HOMI');
    },
  );

  test(
    'unknown microphone name cannot inherit the previous HOMI name',
    () async {
      var connectionCount = 0;
      final control = _control(
        'names',
        (call) async => switch (call.method) {
          'initialize' => oldStatus,
          'requestPermissions' => true,
          'connect' =>
            ++connectionCount == 1
                ? {'phase': 'ready', 'deviceId': 'new', 'deviceName': ''}
                : {'phase': 'ready', 'deviceId': 'another'},
          _ => null,
        },
      );
      await control.connect(device);
      expect(control.status.deviceName, isNull);
      await control.connect(
        const HfpAudioDevice(id: 'another', name: '', isConnected: true),
      );
      expect(control.status.deviceName, isNull);
    },
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

MethodChannelHfpAudioControl _control(
  String suffix,
  Future<Object?> Function(MethodCall) handler,
) {
  final channel = MethodChannel('test_hfp_selection_$suffix');
  final events = EventChannel('test_hfp_selection_$suffix/events');
  final eventMethods = MethodChannel(events.name);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, handler);
  messenger.setMockMethodCallHandler(eventMethods, (_) async => null);
  final control = MethodChannelHfpAudioControl(
    enabled: true,
    methodChannel: channel,
    eventChannel: events,
  );
  addTearDown(() async {
    await control.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(eventMethods, null);
  });
  return control;
}
