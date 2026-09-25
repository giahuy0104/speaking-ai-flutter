import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ailingo_aiv0_ble_control');
  const events = MethodChannel('ailingo_aiv0_ble_control/events');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
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

  test('AIV0 native bridge is enabled on iOS', () async {
    final control = MethodChannelAiv0BleControl(
      enabled: true,
      draftProtocolConfirmed: false,
    );

    expect(control.status.phase, Aiv0BlePhase.idle);
    await control.dispose();
  });

  test(
    'one current listener packet is delivered once and a stale packet is ignored',
    () async {
      final eventChannelCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(events, (call) async {
            eventChannelCalls.add(call);
            return null;
          });
      final control = MethodChannelAiv0BleControl(
        enabled: true,
        draftProtocolConfirmed: false,
      );
      final received = <Aiv0ButtonEvent>[];
      final subscription = control.buttonEvents.listen(received.add);

      await control.initialize();
      final listenCall = eventChannelCalls.singleWhere(
        (call) => call.method == 'listen',
      );
      final listenArguments = listenCall.arguments as Map<Object?, Object?>;
      final generation = (listenArguments['listenerGeneration'] as num).toInt();

      Future<void> emit(int listenerGeneration) async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              events.name,
              const StandardMethodCodec().encodeSuccessEnvelope(
                <String, Object?>{
                  'type': 'button',
                  'listenerGeneration': listenerGeneration,
                  'bytes': <int>[1, 1, 7, 1, 255, 255, 100, 0, 16, 0, 0, 0],
                },
              ),
              (_) {},
            );
        await Future<void>.delayed(Duration.zero);
      }

      await emit(generation - 1);
      await emit(generation);

      expect(received, hasLength(1));
      expect(received.single.button, Aiv0Button.main);
      expect(received.single.gesture, Aiv0ButtonGesture.shortPress);

      await subscription.cancel();
      await control.dispose();
      final cancelCall = eventChannelCalls.singleWhere(
        (call) => call.method == 'cancel',
      );
      expect(
        (cancelCall.arguments as Map<Object?, Object?>)['listenerGeneration'],
        generation,
      );
    },
  );

  test(
    'control context is forwarded without starting audio or recording',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      final control = MethodChannelAiv0BleControl(
        enabled: true,
        draftProtocolConfirmed: false,
      );
      await control.setControlContext(
        learningActive: false,
        diagnosticsActive: true,
      );
      await control.setControlContext(
        learningActive: false,
        diagnosticsActive: false,
      );
      expect(calls.map((call) => call.method), [
        'setControlContext',
        'setControlContext',
      ]);
      expect(calls.first.arguments, {
        'learningActive': false,
        'diagnosticsActive': true,
      });
      expect(calls.last.arguments, {
        'learningActive': false,
        'diagnosticsActive': false,
      });
      await control.dispose();
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test(
      'native observations stay UNKNOWN and never change BLE status on $platform',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final control = MethodChannelAiv0BleControl(
          enabled: true,
          draftProtocolConfirmed: false,
        );
        final received = <Aiv0ButtonEvent>[];
        final subscription = control.buttonEvents.listen(received.add);
        await control.initialize();
        Future<void> emit(Map<String, Object?> event) async {
          await TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .handlePlatformMessage(
                events.name,
                const StandardMethodCodec().encodeSuccessEnvelope(event),
                (_) {},
              );
          await Future<void>.delayed(Duration.zero);
        }

        await emit({'type': 'status', 'phase': 'connected'});
        await emit({
          'type': 'controlObservation',
          'source': platform == TargetPlatform.iOS
              ? 'iosRemoteCommand'
              : 'androidMediaKey',
          'mediaCommand': 'nextTrack',
          'keyCode': 87,
          'action': 0,
          'button': 'main',
          'gesture': 'shortPress',
          'rawPayload': 'private speech token=secret',
          'deviceId': 'test-only-device',
          'receivedAtEpochMs': 1787900045000,
        });
        expect(control.status.phase, Aiv0BlePhase.connected);
        expect(received, hasLength(1));
        expect(received.single.button, Aiv0Button.unknown);
        expect(received.single.gesture, Aiv0ButtonGesture.unknown);
        expect(received.single.isActionable, isFalse);
        expect(
          received.single.rawDescription,
          'command=nextTrack keyCode=87 action=0',
        );
        expect(
          received.single.receivedAt.millisecondsSinceEpoch,
          1787900045000,
        );
        await emit({
          'type': 'button',
          'bytes': [1, 1, 7, 1, 255, 255, 100, 0, 16, 0, 0, 0],
        });
        expect(received, hasLength(2));
        expect(received.last.button, Aiv0Button.main);
        expect(received.last.gesture, Aiv0ButtonGesture.shortPress);
        expect(received.last.isObservedH20Packet, isTrue);
        expect(received.last.isActionable, isTrue);
        await subscription.cancel();
        await control.dispose();
      },
    );
  }

  test('records Parent opening and refreshes the returned timeline', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          if (call.method == 'markParentDiagnosticsOpened') {
            return <Object?, Object?>{
              'phase': 'connected',
              'peripheralState': 'connected',
              'mainNotificationState': 'notifying',
              'diagnosticTimeline': <Object?>[
                <Object?, Object?>{
                  'stage': 'PARENT_SCREEN_OPENED',
                  'caller': 'Aiv0BleControlBridge.methodChannel',
                  'eventEpochMs': 1_787_900_045_000,
                },
              ],
            };
          }
          return null;
        });
    final control = MethodChannelAiv0BleControl(
      enabled: true,
      draftProtocolConfirmed: false,
    );

    await control.markParentDiagnosticsOpened();

    expect(methods, <String>['markParentDiagnosticsOpened']);
    expect(
      control.status.diagnosticTimeline.single.stage,
      'PARENT_SCREEN_OPENED',
    );
    await control.dispose();
  });

  test(
    'serializes Flutter MAIN diagnostics into the native timeline',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      final control = MethodChannelAiv0BleControl(
        enabled: true,
        draftProtocolConfirmed: false,
      );

      await Future.wait<void>(<Future<void>>[
        control.recordMainDiagnostic(
          stage: 'MAIN_DART_RECEIVED',
          values: const <String, Object?>{'sequence': 7},
        ),
        control.recordMainDiagnostic(
          stage: 'MAIN_DART_DISPATCH_COMPLETED',
          values: const <String, Object?>{'result': 'accepted'},
        ),
      ]);

      expect(calls.map((call) => call.method), <String>[
        'recordMainDiagnostic',
        'recordMainDiagnostic',
      ]);
      expect(
        (calls.first.arguments as Map<Object?, Object?>)['stage'],
        'MAIN_DART_RECEIVED',
      );
      expect(
        (calls.last.arguments as Map<Object?, Object?>)['stage'],
        'MAIN_DART_DISPATCH_COMPLETED',
      );
      await control.dispose();
    },
  );
}
