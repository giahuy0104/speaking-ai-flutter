import 'dart:convert';

import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'ten-topic and course-replay prompts play the supplied recordings',
    () async {
      final delegate = _Delegate();
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        enabled: true,
        preferBundledAudio: true,
      );
      addTearDown(service.dispose);
      const prompts = <String, String>{
        'assistant.topic.choose_10.vi':
            'Có 10 Chủ đề. Bạn muốn chọn Chủ đề số mấy?',
        'assistant.topic.invalid_10.vi':
            'Bạn chọn Chủ đề từ số 1 đến số 10 nhé.',
        'assistant.topic.choose_course_relearn.vi':
            'Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Chủ đề số mấy?',
      };
      for (final prompt in prompts.entries) {
        expect(
          await service.authoredPromptBudgetForKey(
            prompt.key,
            text: prompt.value,
          ),
          isNotNull,
        );
        await service.speakAndWaitWithAudioKey(prompt.key, prompt.value);
      }
      expect(delegate.events, ['authored', 'authored', 'authored']);
      expect(
        delegate.authoredAudio.map((bytes) => sha256.convert(bytes).toString()),
        [
          '9366d589707cbc5377920a6a829e5cfbb0f06114fd52011a5c1ef3f5dba0cb85',
          '349f8c3748e2838ae4b5730f471688eaaf08bdb7245ca6d1ff13dec9cd720d6d',
          'c9e71b1b1fa61b3e5e4fa53afb84e83ec8886cc3e6d603f0b7aa95f4c0adafda',
        ],
      );
    },
  );

  test('factory uses platform TTS and preserves text and locale', () async {
    const channel = MethodChannel('ailingo_voice_prompt');
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

    final service = createVoicePromptService();
    addTearDown(service.dispose);
    await service.speakAndWait('  Hello HOMI  ', locale: 'en-US');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'speakAndWait');
    expect(calls.single.arguments, containsPair('text', 'Hello HOMI'));
    expect(calls.single.arguments, containsPair('locale', 'en-US'));
  });

  test('factory never requests authored playback', () async {
    const channel = MethodChannel('ailingo_voice_prompt');
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

    final service = createVoicePromptService();
    addTearDown(service.dispose);
    await service.speak('Xin chào');
    await service.speakAndWait('Bạn muốn học gì?');

    expect(calls.map((call) => call.method), ['speak', 'speakAndWait']);
    expect(
      calls,
      isNot(
        contains(
          predicate<MethodCall>(
            (call) => call.method == 'playAuthoredAudioAndWait',
          ),
        ),
      ),
    );
  });

  test(
    'legacy authored wrapper is disabled by default without manifest load',
    () async {
      final bundle = _TrackingBundle();
      final delegate = _Delegate();
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        bundle: bundle,
      );
      addTearDown(service.dispose);

      expect(await service.authoredPromptBudget('Xin chào'), isNull);
      await service.speak('Một');
      await service.speakAndWait('Hai', locale: 'en-US');
      await service.speakAndWaitOnSelectedMediaOutput('Ba');
      await service.speakAndWaitOnPhoneSpeaker('Bốn');

      expect(bundle.loadCount, 0);
      expect(delegate.events, [
        'speak:Một:vi-VN',
        'wait:Hai:en-US',
        'selected:Ba:vi-VN',
        'phone:Bốn:vi-VN',
      ]);
    },
  );

  test(
    'disabled wrapper preserves stop, dispose, cue, style and MAIN lifecycle',
    () async {
      final delegate = _Delegate();
      final service = MainAssistantAudioPromptService(delegate: delegate);

      await service.playSpeechReadyCue();
      await service.speakAndWaitStyled(
        'Great!',
        locale: 'en-US',
        speechRate: 0.8,
        pitch: 1.1,
      );
      expect(await service.beginMainTurn(), 'turn-1');
      await service.endMainTurn('done', turnId: 'turn-1');
      await service.stop();
      await service.dispose();

      expect(delegate.events, [
        'cue',
        'styled:Great!:en-US:0.8:1.1',
        'begin',
        'end:done:turn-1',
        'stop',
        'stop',
        'dispose',
      ]);
    },
  );

  test('authored assistant audio requires key and matching text', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final bundle = _KeyedBundle(bytes);
    final delegate = _Delegate();
    final service = MainAssistantAudioPromptService(
      delegate: delegate,
      bundle: bundle,
      enabled: true,
      preferBundledAudio: true,
    );
    addTearDown(service.dispose);

    await service.speakAndWaitWithAudioKey(
      'assistant.main.open_menu.vi',
      'Nội dung chuẩn',
    );
    await service.speakAndWaitWithAudioKey(
      'assistant.main.open_menu.vi',
      'Nội dung đã đổi',
    );
    await service.speakAndWaitWithAudioKey(
      'assistant.main.missing.vi',
      'Dùng TTS',
    );

    expect(delegate.events, [
      'authored',
      'wait:Nội dung đã đổi:vi-VN',
      'wait:Dùng TTS:vi-VN',
    ]);
  });
}

class _KeyedBundle extends CachingAssetBundle {
  _KeyedBundle(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(bytes);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    return jsonEncode({
      'schemaVersion': 1,
      'enabled': true,
      'prompts': [
        {
          'key': 'assistant.main.open_menu.vi',
          'enabled': true,
          'locale': 'vi-VN',
          'asset':
              'assets/audio/assistant-core/assistant.main.open_menu.vi.mp3',
          'durationSeconds': 1.0,
          'sha256': sha256.convert(bytes).toString(),
          'text': 'Nội dung chuẩn',
          'textHash': sha256.convert(utf8.encode('Nội dung chuẩn')).toString(),
        },
      ],
    });
  }
}

class _TrackingBundle extends CachingAssetBundle {
  int loadCount = 0;

  @override
  Future<ByteData> load(String key) async {
    loadCount++;
    throw StateError('No authored asset should be loaded: $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    loadCount++;
    throw StateError('No authored manifest should be loaded: $key');
  }
}

class _Delegate
    implements
        VoicePromptService,
        AuthoredAudioVoicePromptService,
        SpeechReadyCuePlayer,
        PhoneSpeakerVoicePromptService,
        SelectedMediaOutputVoicePromptService,
        StyledMediaOutputVoicePromptService,
        MainTurnVoicePromptService {
  final events = <String>[];
  final authoredAudio = <Uint8List>[];

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    events.add('speak:$text:$locale');
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    events.add('wait:$text:$locale');
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) async {
    events.add('selected:$text:$locale');
  }

  @override
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  }) async {
    events.add('phone:$text:$locale');
  }

  @override
  Future<void> speakAndWaitStyled(
    String text, {
    required String locale,
    required double speechRate,
    required double pitch,
  }) async {
    events.add('styled:$text:$locale:$speechRate:$pitch');
  }

  @override
  Future<void> playAuthoredAudioAndWait(
    Uint8List bytes, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) async {
    events.add('authored');
    authoredAudio.add(bytes);
  }

  @override
  Future<void> playSpeechReadyCue() async {
    events.add('cue');
  }

  @override
  Future<String?> beginMainTurn() async {
    events.add('begin');
    return 'turn-1';
  }

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    events.add('end:$reason:$turnId');
  }

  @override
  Future<void> stop() async {
    events.add('stop');
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
  }
}
