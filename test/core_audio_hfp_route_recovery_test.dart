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
    MethodCall? connectCall;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return <String, dynamic>{'phase': 'idle'};
        case 'requestPermissions':
          return true;
        case 'connect':
          connectCall = call;
          return <String, dynamic>{
            'phase': 'ready',
            'deviceId': 'hm-d001',
            'deviceName': 'HM-D001',
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
      const HfpAudioDevice(id: 'hm-d001', name: 'HM-D001', isConnected: true),
    );

    expect(control.status.isConnected, isTrue);
    expect(control.status.deviceId, 'hm-d001');
    expect(control.status.routeActive, isFalse);
    expect(connectCall?.arguments, <String, dynamic>{
      'deviceId': 'hm-d001',
      'deviceName': 'HM-D001',
    });
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
            'deviceId': 'old-hm-d001-uid',
            'deviceName': 'HM-D001',
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
            'deviceId': 'new-hm-d001-uid',
            'deviceName': 'HM-D001',
            'routeActive': true,
            'inputDeviceName': 'HM-D001',
            'outputDeviceName': 'HM-D001',
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
    expect(control.status.deviceId, 'new-hm-d001-uid');
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
            'deviceId': 'hm-d001',
            'deviceName': 'HM-D001',
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
            'deviceId': 'hm-d001',
            'deviceName': 'HM-D001',
            'routeActive': true,
            'inputDeviceName': 'HM-D001',
            'outputDeviceName': 'HM-D001',
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
    'rejects a route snapshot without both selected HM-D001 endpoints',
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
              'deviceId': 'hm-d001',
              'deviceName': 'HM-D001',
            };
          case 'startAudioRoute':
            return <String, dynamic>{
              'phase': 'recording',
              'deviceId': 'hm-d001',
              'deviceName': 'HM-D001',
              'routeActive': true,
              'inputDeviceName': 'HM-D001',
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
            'deviceId': 'hm-d001',
            'deviceName': 'HM-D001',
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
