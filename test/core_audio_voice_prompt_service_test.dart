import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service_native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android awaited TTS failure propagates to the capture gate', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('test_failed_model');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'HFP_ROUTE_LOST');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const service = MethodChannelVoicePromptService(channel: channel);
    await expectLater(
      service.speakAndWait('Model'),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
      service.speakAndWaitOnSelectedMediaOutput('Model'),
      throwsA(isA<PlatformException>()),
    );
  });

  test(
    'translation style stays per utterance and leaves prompt defaults intact',
    () async {
      const channel = MethodChannel('test_translation_style');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const service = MethodChannelVoicePromptService(channel: channel);
      await service.speakAndWaitStyled(
        'I like apples.',
        locale: 'en-US',
        speechRate: 0.85,
        pitch: 1.05,
      );
      await service.speakAndWait('Giỏi lắm!');
      final styled = calls.first.arguments as Map<Object?, Object?>;
      expect(styled['speechRate'], 0.85);
      expect(styled['pitch'], 1.05);
      expect(styled['forceMediaPlayback'], true);
      final normal = calls.last.arguments as Map<Object?, Object?>;
      expect(normal.containsKey('speechRate'), false);
      expect(normal.containsKey('pitch'), false);
    },
  );

  test('sends the Vietnamese retry prompt through the native bridge', () async {
    const channel = MethodChannel('test_voice_prompt');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelVoicePromptService(channel: channel);
    await service.speak('Con đưa micro lại gần và nói rõ hơn nhé.');

    expect(receivedCall?.method, 'speak');
    expect(receivedCall?.arguments, <String, dynamic>{
      'text': 'Con đưa micro lại gần và nói rõ hơn nhé.',
      'locale': 'vi-VN',
      'gainDb': 8.0,
      'forcePhoneSpeaker': false,
      'forceMediaPlayback': false,
    });
  });

  test(
    'waits for the wake acknowledgement through the native bridge',
    () async {
      const channel = MethodChannel('test_voice_prompt_wait');
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            receivedCall = call;
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      const service = MethodChannelVoicePromptService(channel: channel);
      await service.speakAndWait('HOMI nghe đây.');

      expect(receivedCall?.method, 'speakAndWait');
      expect(receivedCall?.arguments, <String, dynamic>{
        'text': 'HOMI nghe đây.',
        'locale': 'vi-VN',
        'gainDb': 8.0,
        'forcePhoneSpeaker': false,
        'forceMediaPlayback': false,
      });
    },
  );

  test('marks listening coach speech for the phone speaker', () async {
    const channel = MethodChannel('test_phone_speaker_prompt');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelVoicePromptService(channel: channel);
    await service.speakAndWaitOnPhoneSpeaker('Nói theo cô nhé.');

    expect(receivedCall?.method, 'speakAndWait');
    expect(receivedCall?.arguments, <String, dynamic>{
      'text': 'Nói theo cô nhé.',
      'locale': 'vi-VN',
      'gainDb': 8.0,
      'forcePhoneSpeaker': true,
      'forceMediaPlayback': false,
    });
  });

  test('marks lesson speech for selected H20 output', () async {
    const channel = MethodChannel('test_media_output_prompt');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelVoicePromptService(channel: channel);
    await service.speakAndWaitOnSelectedMediaOutput('Con nói lại nhé.');

    expect(receivedCall?.method, 'speakAndWait');
    expect(receivedCall?.arguments, <String, dynamic>{
      'text': 'Con nói lại nhé.',
      'locale': 'vi-VN',
      'gainDb': 8.0,
      'forcePhoneSpeaker': false,
      'forceMediaPlayback': true,
    });
  });

  test('waits for the speech-ready cue through the native bridge', () async {
    const channel = MethodChannel('test_speech_ready_cue');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelVoicePromptService(channel: channel);
    await service.playSpeechReadyCue();

    expect(receivedCall?.method, 'playSpeechReadyCue');
    expect(receivedCall?.arguments, isNull);
  });

  test('ready cue does not finish before native output has drained', () async {
    const channel = MethodChannel('test_ready_cue_completion_gate');
    final cueFinished = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => cueFinished.future);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    const service = MethodChannelVoicePromptService(channel: channel);
    var completed = false;
    final pending = service.playSpeechReadyCue().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    cueFinished.complete();
    await pending;
    expect(completed, isTrue);
  });

  for (final code in ['READY_CUE_UNAVAILABLE', 'HFP_ROUTE_LOST']) {
    test('Android $code fails the ready gate instead of opening mic', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('test_ready_cue_failure');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: code);
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      const service = MethodChannelVoicePromptService(channel: channel);
      await expectLater(
        service.playSpeechReadyCue(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
    });
  }

  test('brackets one MAIN turn through the native coordinator', () async {
    const channel = MethodChannel('test_main_turn_prompt');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'beginMainTurn') return 'ios-main-test';
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelVoicePromptService(channel: channel);
    expect(await service.beginMainTurn(), 'ios-main-test');
    await service.endMainTurn('test_complete', turnId: 'ios-main-test');

    expect(calls.map((call) => call.method), <String>[
      'beginMainTurn',
      'endMainTurn',
    ]);
    expect(calls.last.arguments, <String, dynamic>{
      'reason': 'test_complete',
      'turnId': 'ios-main-test',
    });
  });
}
