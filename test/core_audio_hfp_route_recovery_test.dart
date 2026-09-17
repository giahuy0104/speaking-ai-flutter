import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connect applies the authoritative HFP snapshot immediately', () async {
    const methodChannel = MethodChannel('test_hfp_connect_snapshot');
    const eventChannel = EventChannel('test_hfp_connect_snapshot/events');
    const eventMethodChannel = MethodChannel(
      'test_hfp_connect_snapshot/events',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(eventMethodChannel, (_) async => null);
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return <String, dynamic>{'phase': 'idle'};
        case 'requestPermissions':
          return true;
        case 'connect':
          return <String, dynamic>{
            'phase': 'ready',
            'deviceId': 'h20',
            'deviceName': 'H20',
            'routeActive': false,
          };
        case 'stopAudioRoute':
          return null;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockMethodCallHandler(eventMethodChannel, null);
    });
    final control = MethodChannelHfpAudioControl(
      enabled: true,
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    addTearDown(control.dispose);

    await control.connect(
      const HfpAudioDevice(id: 'h20', name: 'H20', isConnected: true),
    );

    expect(control.status.isConnected, isTrue);
    expect(control.status.deviceId, 'h20');
    expect(control.status.routeActive, isFalse);
  });

  test('retries a transient iOS HFP route-unavailable transition', () async {
    const methodChannel = MethodChannel('test_hfp_route_recovery');
    const eventChannel = EventChannel('test_hfp_route_recovery/events');
    const eventMethodChannel = MethodChannel('test_hfp_route_recovery/events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var startCalls = 0;
    messenger.setMockMethodCallHandler(eventMethodChannel, (_) async => null);
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return <String, dynamic>{
            'phase': 'ready',
            'deviceId': 'old-h20-uid',
            'deviceName': 'H20',
            'routeActive': false,
          };
        case 'startAudioRoute':
          startCalls += 1;
          if (startCalls == 1) {
            throw PlatformException(
              code: 'HFP_ROUTE_UNAVAILABLE',
              message: 'HFP input is still returning after media playback.',
            );
          }
          return <String, dynamic>{
            'phase': 'recording',
            'deviceId': 'new-h20-uid',
            'deviceName': 'H20',
            'routeActive': true,
            'inputDeviceName': 'H20',
            'outputDeviceName': 'H20',
          };
        case 'stopAudioRoute':
          return null;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockMethodCallHandler(eventMethodChannel, null);
    });
    final control = MethodChannelHfpAudioControl(
      enabled: true,
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    addTearDown(control.dispose);

    await control.startAudioRoute();

    expect(startCalls, 2);
    expect(control.status.routeActive, isTrue);
    expect(control.status.deviceId, 'new-h20-uid');
  });

  test('retries a transient Android HFP route failure', () async {
    const methodChannel = MethodChannel('test_android_hfp_route_recovery');
    const eventChannel = EventChannel('test_android_hfp_route_recovery/events');
    const eventMethodChannel = MethodChannel(
      'test_android_hfp_route_recovery/events',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var startCalls = 0;
    messenger.setMockMethodCallHandler(eventMethodChannel, (_) async => null);
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return <String, dynamic>{
            'phase': 'ready',
            'deviceId': 'h20',
            'deviceName': 'H20',
            'routeActive': false,
          };
        case 'startAudioRoute':
          startCalls += 1;
          if (startCalls == 1) {
            throw PlatformException(
              code: 'HFP_ROUTE_FAILED',
              message: 'Android SCO route is still settling.',
            );
          }
          return <String, dynamic>{
            'phase': 'recording',
            'deviceId': 'h20',
            'deviceName': 'H20',
            'routeActive': true,
            'inputDeviceName': 'H20',
            'outputDeviceName': 'H20',
          };
        case 'stopAudioRoute':
          return null;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockMethodCallHandler(eventMethodChannel, null);
    });
    final control = MethodChannelHfpAudioControl(
      enabled: true,
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    addTearDown(control.dispose);

    await control.startAudioRoute();

    expect(startCalls, 2);
    expect(control.status.routeActive, isTrue);
  });

  test(
    'rejects a route snapshot without both selected H20 endpoints',
    () async {
      const methodChannel = MethodChannel('test_incomplete_hfp_route');
      const eventChannel = EventChannel('test_incomplete_hfp_route/events');
      const eventMethodChannel = MethodChannel(
        'test_incomplete_hfp_route/events',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(eventMethodChannel, (_) async => null);
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        switch (call.method) {
          case 'initialize':
            return <String, dynamic>{
              'phase': 'ready',
              'deviceId': 'h20',
              'deviceName': 'H20',
            };
          case 'startAudioRoute':
            return <String, dynamic>{
              'phase': 'recording',
              'deviceId': 'h20',
              'deviceName': 'H20',
              'routeActive': true,
              'inputDeviceName': 'H20',
              'outputDeviceName': null,
            };
          case 'stopAudioRoute':
            return null;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(methodChannel, null);
        messenger.setMockMethodCallHandler(eventMethodChannel, null);
      });
      final control = MethodChannelHfpAudioControl(
        enabled: true,
        methodChannel: methodChannel,
        eventChannel: eventChannel,
      );
      addTearDown(control.dispose);

      await expectLater(
        control.startAudioRoute(),
        throwsA(isA<HfpAudioException>()),
      );
    },
  );

  test('stop invalidates a pending route retry', () async {
    const methodChannel = MethodChannel('test_hfp_route_cancel');
    const eventChannel = EventChannel('test_hfp_route_cancel/events');
    const eventMethodChannel = MethodChannel('test_hfp_route_cancel/events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var startCalls = 0;
    var stopCalls = 0;
    messenger.setMockMethodCallHandler(eventMethodChannel, (_) async => null);
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return <String, dynamic>{
            'phase': 'ready',
            'deviceId': 'h20',
            'deviceName': 'H20',
            'routeActive': false,
          };
        case 'startAudioRoute':
          startCalls += 1;
          throw PlatformException(
            code: 'HFP_ROUTE_UNAVAILABLE',
            message: 'Route is settling.',
          );
        case 'stopAudioRoute':
          stopCalls += 1;
          return null;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockMethodCallHandler(eventMethodChannel, null);
    });
    final control = MethodChannelHfpAudioControl(
      enabled: true,
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    addTearDown(control.dispose);

    final pendingStart = control.startAudioRoute();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await control.stopAudioRoute();
    await pendingStart.timeout(const Duration(milliseconds: 400));

    expect(startCalls, 1);
    expect(stopCalls, 1);
  });
}
