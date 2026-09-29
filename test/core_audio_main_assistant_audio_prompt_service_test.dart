import 'dart:convert';

import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_loudness_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(AudioLoudnessManifest.resetForTesting);
  tearDown(AudioLoudnessManifest.resetForTesting);

  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('authored MAIN audio plays at its measured level', () async {
    // MAIN's navigation lines are the clearest place a child hears the
    // catalogue's unevenness, because they play between everything else.
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final delegate = _Delegate();
    final service = MainAssistantAudioPromptService(
      delegate: delegate,
      bundle: _KeyedBundle(bytes),
      enabled: true,
      preferBundledAudio: true,
    );
    addTearDown(service.dispose);

    await service.speakAndWaitWithAudioKey(
      'assistant.main.open_menu.vi',
      'Nội dung chuẩn',
    );

    expect(delegate.events, ['authored']);
    expect(delegate.lastAuthoredGainDb, -7.5);
  });

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

  test('a failed manifest load is retried on the next prompt', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final bundle = _FlakyManifestBundle(bytes, failuresBeforeSuccess: 1);
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
      'Nội dung chuẩn',
    );

    expect(bundle.manifestLoads, 2);
    expect(delegate.events, ['wait:Nội dung chuẩn:vi-VN', 'authored']);
  });

  test('concurrent prompts share one successful manifest load', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final bundle = _FlakyManifestBundle(bytes, failuresBeforeSuccess: 0);
    final delegate = _Delegate();
    final service = MainAssistantAudioPromptService(
      delegate: delegate,
      bundle: bundle,
      enabled: true,
      preferBundledAudio: true,
    );
    addTearDown(service.dispose);

    await Future.wait(<Future<void>>[
      service.speakAndWaitWithAudioKey(
        'assistant.main.open_menu.vi',
        'Nội dung chuẩn',
      ),
      service.speakAndWaitWithAudioKey(
        'assistant.main.open_menu.vi',
        'Nội dung chuẩn',
      ),
    ]);

    expect(bundle.manifestLoads, 1);
    expect(delegate.events, ['authored', 'authored']);
  });

  test('a manifest that lost an optional pack is not memoised', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    const extra = 'assets/data/optional_pack.json';
    final bundle = _FlakyManifestBundle(
      bytes,
      failuresBeforeSuccess: 0,
      failingExtraAsset: extra,
    );
    final delegate = _Delegate();
    final service = MainAssistantAudioPromptService(
      delegate: delegate,
      bundle: bundle,
      enabled: true,
      preferBundledAudio: true,
      additionalManifestAssets: const <String>[extra],
    );
    addTearDown(service.dispose);

    await service.speakAndWaitWithAudioKey(
      'assistant.main.open_menu.vi',
      'Nội dung chuẩn',
    );
    await service.speakAndWaitWithAudioKey(
      'assistant.main.open_menu.vi',
      'Nội dung chuẩn',
    );

    expect(bundle.extraLoads, 2, reason: 'the missing pack must be retried');
    expect(bundle.manifestLoads, 2);
    expect(delegate.events, ['authored', 'authored']);
  });

  test('a load cancelled by stop does not poison the next prompt', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final bundle = _FlakyManifestBundle(bytes, failuresBeforeSuccess: 1);
    final delegate = _Delegate();
    final service = MainAssistantAudioPromptService(
      delegate: delegate,
      bundle: bundle,
      enabled: true,
      preferBundledAudio: true,
    );
    addTearDown(service.dispose);

    final first = service.speakAndWaitWithAudioKey(
      'assistant.main.open_menu.vi',
      'Nội dung chuẩn',
    );
    await service.stop();
    await first;

    await service.speakAndWaitWithAudioKey(
      'assistant.main.open_menu.vi',
      'Nội dung chuẩn',
    );

    expect(bundle.manifestLoads, 2);
    expect(delegate.events.last, 'authored');
  });
}

class _FlakyManifestBundle extends CachingAssetBundle {
  _FlakyManifestBundle(
    this.bytes, {
    required this.failuresBeforeSuccess,
    this.failingExtraAsset,
  });

  final Uint8List bytes;
  final int failuresBeforeSuccess;
  final String? failingExtraAsset;
  int manifestLoads = 0;
  int extraLoads = 0;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(bytes);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    // Counting prompt-manifest loads: the loudness lookup is a different
    // asset and must not register as one.
    if (key == AudioLoudnessManifest.assetKey) {
      return jsonEncode(<String, Object?>{'gainDb': <String, Object?>{}});
    }
    if (key == failingExtraAsset) {
      extraLoads++;
      throw StateError('Optional pack unavailable');
    }
    manifestLoads++;
    if (manifestLoads <= failuresBeforeSuccess) {
      throw StateError('Manifest unavailable');
    }
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

class _KeyedBundle extends CachingAssetBundle {
  _KeyedBundle(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(bytes);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == AudioLoudnessManifest.assetKey) {
      return jsonEncode({
        'policy': {'targetRmsDbfs': -21.0},
        'gainDb': {
          'assets/audio/assistant-core/assistant.main.open_menu.vi.mp3': -7.5,
        },
      });
    }
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
    // Counting prompt-manifest loads: the loudness lookup is a different
    // asset and must not register as one.
    if (key == AudioLoudnessManifest.assetKey) {
      return jsonEncode(<String, Object?>{'gainDb': <String, Object?>{}});
    }
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
  double? lastAuthoredGainDb;
  final events = <String>[];

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
    double? gainDb,
  }) async {
    lastAuthoredGainDb = gainDb;
    events.add('authored');
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
