import 'dart:async';

import 'package:ai_speaking_flutter_app/core/platform/background_learning_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS explicit foreground resume requires native confirmation', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('test_foreground_audio_resume');
    final calls = <String>[];
    bool? allowed = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return allowed;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    final session = MethodChannelBackgroundLearningSession(
      methodChannel: channel,
    );
    expect(await session.resumeForegroundAudio(), isTrue);
    allowed = null;
    expect(await session.resumeForegroundAudio(), isFalse);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'FOREGROUND_AUDIO_RESUME_DENIED');
    });
    expect(await session.resumeForegroundAudio(), isFalse);
    expect(calls, ['resumeForegroundAudio', 'resumeForegroundAudio']);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await session.resumeForegroundAudio(), isTrue);
    expect(calls, hasLength(2));
  });

  testWidgets(
    'hung iOS explicit resume times out without starting audio',
    (tester) async {
      const channel = MethodChannel('test_foreground_audio_resume_timeout');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final pending = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (_) => pending.future);
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
      });
      final session = MethodChannelBackgroundLearningSession(
        methodChannel: channel,
      );
      final resumed = session.resumeForegroundAudio();
      await tester.pump(const Duration(seconds: 3));
      expect(await resumed, isFalse);
      pending.complete(true);
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  group('BackgroundLearningEvent.fromRaw', () {
    test('maps a native interruption without losing its reason', () {
      final event = BackgroundLearningEvent.fromRaw(<Object?, Object?>{
        'type': 'background.interrupted',
        'reason': 'audio_focus_loss',
      });

      expect(event.type, BackgroundLearningEventType.interrupted);
      expect(event.reason, 'audio_focus_loss');
    });

    test('maps a resumable native audio session event', () {
      final event = BackgroundLearningEvent.fromRaw(<Object?, Object?>{
        'type': 'background.resumable',
        'reason': 'audio_session_interruption_ended',
      });

      expect(event.type, BackgroundLearningEventType.resumable);
      expect(event.reason, 'audio_session_interruption_ended');
    });

    test('treats stopped and malformed payloads as stopped', () {
      expect(
        BackgroundLearningEvent.fromRaw(<String, String>{
          'type': 'background.stopped',
        }).type,
        BackgroundLearningEventType.stopped,
      );
      expect(
        BackgroundLearningEvent.fromRaw('invalid').type,
        BackgroundLearningEventType.stopped,
      );
    });
  });

  test('forwards the active lesson wake state to Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('test_background_learning');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    final session = MethodChannelBackgroundLearningSession(
      methodChannel: channel,
    );
    await session.setActiveLearning(true);
    await session.setActiveLearning(false);

    expect(calls.map((call) => call.method), <String>[
      'setActiveLearning',
      'setActiveLearning',
    ]);
    expect(calls.first.arguments, <String, bool>{'active': true});
    expect(calls.last.arguments, <String, bool>{'active': false});
  });

  test('reads whether the Android display is interactive', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('test_background_screen_state');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return false;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    final interactive = await MethodChannelBackgroundLearningSession(
      methodChannel: channel,
    ).isScreenInteractive();

    expect(interactive, isFalse);
    expect(captured?.method, 'isScreenInteractive');
  });

  test(
    'requests parent-visible HM-D001 companion association on Android',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('test_background_companion');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      MethodCall? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return <Object?, Object?>{
          'supported': true,
          'associated': true,
          'deviceId': 'AA:BB:CC:DD:EE:FF',
        };
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(channel, null);
      });

      final associated = await MethodChannelBackgroundLearningSession(
        methodChannel: channel,
      ).associateHomiCompanion('AA:BB:CC:DD:EE:FF');

      expect(associated, isTrue);
      expect(captured?.method, 'companion.associate');
      expect(captured?.arguments, <String, Object?>{
        'deviceId': 'AA:BB:CC:DD:EE:FF',
      });
    },
  );
}
