import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/audio_gain.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_turn_coordinator.dart';
import 'package:ai_speaking_flutter_app/core/audio/coordinated_voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_cloudinary_audio_client.dart';

const _text = MainVoiceAssistantFlow.openingPrompt;
const _asset = 'assets/audio/MAIN/AI-001.vi.v1.mp3';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'optional curriculum pack plays locally with its duration budget',
    () async {
      final delegate = _Delegate();
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        bundle: _CurriculumBundle(),
        additionalManifestAssets: const ['curriculum.json'],
      );
      expect(
        await service.authoredPromptBudget('Câu bài học.'),
        const Duration(seconds: 24),
      );
      await service.speakAndWait('Câu bài học.');
      await service.speakAndWait(_text);
      expect(delegate.events, ['audio:normal', 'audio:normal']);
      await service.dispose();
    },
  );

  for (final mode in ['missing', 'invalid', 'disabled']) {
    test(
      'an $mode optional curriculum pack preserves MAIN and fallback',
      () async {
        final delegate = _Delegate();
        final service = MainAssistantAudioPromptService(
          delegate: delegate,
          bundle: _CurriculumBundle(extraMode: mode),
          additionalManifestAssets: const ['curriculum.json'],
        );
        await service.speakAndWait(_text);
        await service.speakAndWait('Câu bài học.');
        expect(delegate.events, ['audio:normal', 'tts:vi-VN:Câu bài học.']);
        await service.dispose();
      },
    );
  }

  for (final stage in ['manifest', 'asset', 'playback']) {
    testWidgets('dispose cancels pending $stage timer immediately', (
      tester,
    ) async {
      final delegate = _Delegate()..blockPlayback = stage == 'playback';
      final bundle = _Bundle()
        ..blockManifest = stage == 'manifest'
        ..blockAsset = stage == 'asset';
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        bundle: bundle,
      );
      final play = service.speakAndWait(_text);
      await tester.pump();
      await service.dispose();
      await play;
      expect(
        delegate.events.where((event) => event.startsWith('tts:')),
        isEmpty,
      );
      // Do not complete the underlying operation. The test binding checks that
      // no timer survives disposal, even if asset/native I/O never replies.
    });
  }

  test(
    'authored timeout budget is duration aware; unknown text keeps default',
    () async {
      final service = MainAssistantAudioPromptService(
        delegate: _Delegate(),
        bundle: _Bundle(mode: 'long'),
      );
      expect(
        await service.authoredPromptBudget(_text),
        const Duration(seconds: 19),
      );
      expect(await service.authoredPromptBudget('Dynamic text'), isNull);
      final coordinator = AudioTurnCoordinator();
      addTearDown(coordinator.dispose);
      final coordinated = CoordinatedVoicePromptService(
        delegate: service,
        coordinator: coordinator,
        owner: AudioTurnOwner.mainAssistant,
      );
      expect(
        await coordinated.authoredPromptBudget(_text),
        const Duration(seconds: 19),
      );
      expect(coordinator.hasActiveTurn, false);
    },
  );

  test(
    'English feedback can match the explicit legacy Vietnamese lookup locale',
    () async {
      final delegate = _Delegate();
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        bundle: _Bundle(mode: 'english'),
      );
      await service.speakAndWait('Great!', locale: 'vi-VN');
      expect(delegate.events, ['audio:normal']);
      await service.speakAndWait('Great!', locale: 'fr-FR');
      expect(delegate.events.last, 'tts:fr-FR:Great!');
    },
  );

  test(
    'real pilot matches runtime text, voices, speeds, checksum and watchdog',
    () async {
      final manifest =
          jsonDecode(
                await File(
                  MainAssistantAudioPromptService.manifestAsset,
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(manifest['modelId'], 'eleven_v3');
      expect(manifest['profiles'], {
        'en': {'voiceId': 'Nhs7eitvQWFTQBsf0yiT', 'speed': 0.75},
        'vi': {'voiceId': '5CVDNcIPiOYgRUQuxXd7', 'speed': 0.9},
      });
      final entry = (manifest['prompts'] as List).cast<Map>().singleWhere(
        (entry) => entry['text'] == _text,
      );
      expect(entry['text'], _text);
      expect(
        entry['durationSeconds'],
        lessThanOrEqualTo(MainAssistantAudioPromptService.maximumAudioSeconds),
      );
      final bytes = await File(entry['asset'] as String).readAsBytes();
      expect(sha256.convert(bytes).toString(), entry['sha256']);
      expect(
        entry['group'],
        MainAssistantAudioPromptService.mainNavigationGroup,
      );
      final receipt =
          jsonDecode(await File('${entry['asset']}.json').readAsString())
              as Map;
      expect(receipt['request']['model_id'], 'eleven_v3');
      expect(receipt['speed'], 0.9);
      expect(receipt['speedMethod'], 'ffmpeg-atempo');
      expect(receipt['request']['voice_settings']['speed'], 1.0);
      expect(receipt['finalSha256'], entry['sha256']);
    },
  );

  test(
    'plays only exact text and locale, waiting for audio completion',
    () async {
      final delegate = _Delegate()..blockPlayback = true;
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        bundle: _Bundle(),
      );
      var completed = false;
      final play = service
          .speakAndWaitOnSelectedMediaOutput(_text)
          .then((_) => completed = true);
      await delegate.started.future;
      expect(completed, false);
      expect(delegate.events, ['audio:selected']);
      delegate.playback.complete();
      await play;
      expect(completed, true);
      await service.speakAndWait('A different prompt');
      await service.speakAndWait(_text, locale: 'en-US');
      expect(delegate.events.skip(1), [
        'tts:vi-VN:A different prompt',
        'tts:en-US:$_text',
      ]);
    },
  );

  test(
    'missing, disabled, corrupted and mismatched entries keep existing TTS',
    () async {
      for (final mode in [
        'disabled',
        'missing',
        'hash',
        'text',
        'too-long',
        'duplicate',
        'manifest',
        'duration',
      ]) {
        final delegate = _Delegate();
        final bundle = _Bundle(mode: mode);
        await MainAssistantAudioPromptService(
          delegate: delegate,
          bundle: bundle,
        ).speakAndWait(_text);
        expect(delegate.events, ['tts:vi-VN:$_text'], reason: mode);
      }
    },
  );

  test('feature switch avoids even reading the manifest', () async {
    final delegate = _Delegate();
    final bundle = _Bundle();
    await MainAssistantAudioPromptService(
      delegate: delegate,
      bundle: bundle,
      enabled: false,
    ).speakAndWait(_text);
    expect(bundle.manifestLoads, 0);
    expect(delegate.events, ['tts:vi-VN:$_text']);
  });

  test(
    'a disabled audio group falls back without disabling other groups',
    () async {
      final disabledDelegate = _Delegate();
      await MainAssistantAudioPromptService(
        delegate: disabledDelegate,
        bundle: _Bundle(mode: 'grouped'),
        groupEnabled: const {
          MainAssistantAudioPromptService.challengeCueGroup: false,
        },
      ).speakAndWait(_text);
      expect(disabledDelegate.events, ['tts:vi-VN:$_text']);

      final enabledDelegate = _Delegate();
      await MainAssistantAudioPromptService(
        delegate: enabledDelegate,
        bundle: _Bundle(mode: 'grouped'),
        groupEnabled: const {
          MainAssistantAudioPromptService.challengeCueGroup: true,
        },
      ).speakAndWait(_text);
      expect(enabledDelegate.events, ['audio:normal']);
    },
  );

  test(
    'native playback failure stops failed audio before one TTS fallback',
    () async {
      final delegate = _Delegate()..failPlayback = true;
      await MainAssistantAudioPromptService(
        delegate: delegate,
        bundle: _Bundle(),
      ).speakAndWait(_text);
      expect(delegate.events, ['audio:normal', 'stop', 'tts:vi-VN:$_text']);
    },
  );

  for (final code in [
    'HFP_ROUTE_LOST',
    'HFP_ROUTE_FAILED',
    'HFP_ROUTE_TIMEOUT',
    'HFP_ROUTE_CANCELLED',
  ]) {
    test('$code propagates without replaying TTS on phone output', () async {
      final failure = PlatformException(code: code);
      final delegate = _Delegate()..playbackError = failure;
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        bundle: _Bundle(),
      );
      addTearDown(service.dispose);

      await expectLater(
        service.speakAndWaitOnSelectedMediaOutput(_text),
        throwsA(same(failure)),
      );
      expect(delegate.events, ['audio:selected', 'stop']);
    });
  }

  test(
    'stop during asset loading cannot start audio or fallback TTS',
    () async {
      final delegate = _Delegate();
      final bundle = _Bundle()..blockAsset = true;
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        bundle: bundle,
      );
      final play = service.speakAndWait(_text);
      await bundle.assetStarted.future;
      await service.stop();
      bundle.assetCompletion.complete();
      await play;
      expect(delegate.events, ['stop']);
      await service.speakAndWait('New turn');
      expect(delegate.events.last, 'tts:vi-VN:New turn');
    },
  );

  test(
    'stop during failing playback cannot resurrect the canceled prompt',
    () async {
      final delegate = _Delegate()..blockPlayback = true;
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        bundle: _Bundle(),
      );
      final play = service.speakAndWait(_text);
      await delegate.started.future;
      await service.stop();
      delegate.playback.completeError(StateError('Canceled decoder'));
      await play;
      expect(delegate.events, ['audio:normal', 'stop']);
    },
  );

  test('load timeout is bounded and late asset result cannot play', () async {
    final delegate = _Delegate();
    final bundle = _Bundle()..blockAsset = true;
    final service = MainAssistantAudioPromptService(
      delegate: delegate,
      bundle: bundle,
      assetLoadTimeout: const Duration(milliseconds: 10),
    );
    await service.speakAndWait(_text);
    bundle.assetCompletion.complete();
    await Future<void>.delayed(Duration.zero);
    expect(delegate.events, ['tts:vi-VN:$_text']);
  });

  test('disposal during loading prevents late playback', () async {
    final delegate = _Delegate();
    final bundle = _Bundle()..blockAsset = true;
    final service = MainAssistantAudioPromptService(
      delegate: delegate,
      bundle: bundle,
    );
    final play = service.speakAndWait(_text);
    await bundle.assetStarted.future;
    await service.dispose();
    bundle.assetCompletion.complete();
    await play;
    await service.speakAndWait(_text);
    expect(delegate.events, ['stop', 'dispose']);
  });

  test(
    'phone route, ready cue, native MAIN lease and style are forwarded',
    () async {
      final delegate = _Delegate();
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        bundle: _Bundle(),
      );
      expect(await service.beginMainTurn(), 'main-1');
      await service.speakAndWaitOnPhoneSpeaker(_text);
      await service.playSpeechReadyCue();
      await service.speakAndWaitStyled(
        _text,
        locale: 'vi-VN',
        speechRate: 0.8,
        pitch: 1.1,
      );
      await service.endMainTurn('done', turnId: 'main-1');
      expect(delegate.events, [
        'begin',
        'audio:phone',
        'cue',
        'style:0.8:1.1',
        'end:done:main-1',
      ]);
    },
  );

  test(
    'authored playback retains one lease until done, then allows recording',
    () async {
      final coordinator = AudioTurnCoordinator();
      addTearDown(coordinator.dispose);
      final delegate = _Delegate()..blockPlayback = true;
      final service = CoordinatedVoicePromptService(
        delegate: MainAssistantAudioPromptService(
          delegate: delegate,
          bundle: _Bundle(),
        ),
        coordinator: coordinator,
        owner: AudioTurnOwner.mainAssistant,
      );
      final play = service.speakAndWait(_text);
      await delegate.started.future;
      expect(coordinator.currentToken?.owner, AudioTurnOwner.mainAssistant);
      var recordingAcquired = false;
      final recording = coordinator
          .acquire(
            owner: AudioTurnOwner.listeningLesson,
            mode: AudioTurnMode.recordedCapture,
          )
          .then((lease) {
            recordingAcquired = true;
            return lease;
          });
      await Future<void>.delayed(Duration.zero);
      expect(recordingAcquired, false);
      delegate.playback.complete();
      await play;
      final lease = await recording;
      expect(recordingAcquired, true);
      await lease.release();
    },
  );

  test(
    'MAIN opening and Core retries use the updated navigation recordings',
    () async {
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
      final service = createVoicePromptService(
        owner: AudioTurnOwner.mainAssistant,
        httpClient: createLocalCloudinaryAudioClient(),
      );
      addTearDown(service.dispose);
      final flow = MainVoiceAssistantFlow();

      await service.speakAndWait(flow.begin());
      final corePrompt = flow.beginActiveLearning(
        kind: ActiveLearningModuleKind.listeningLesson,
      );
      await service.speakAndWait(corePrompt);
      final echo = await flow.handle(corePrompt);
      await service.speakAndWait(echo.promptText);

      expect(calls.map((call) => call.method), [
        'playAuthoredAudioAndWait',
        'playAuthoredAudioAndWait',
        'playAuthoredAudioAndWait',
      ]);
      final expectedAssets = [
        'assets/audio/MAIN/RUNTIME-MAIN-NAVIGATION-001.vi.v1.mp3',
        'assets/audio/MAIN/GAP66/GAP66-002.vi.v1.mp3',
        'assets/audio/MAIN/GAP66/GAP66-002.vi.v1.mp3',
      ];
      for (var index = 0; index < calls.length; index++) {
        final playedBytes =
            (calls[index].arguments as Map)['bytes'] as Uint8List;
        final expectedBytes = await File(expectedAssets[index]).readAsBytes();
        expect(
          sha256.convert(playedBytes).toString(),
          sha256.convert(expectedBytes).toString(),
          reason: expectedAssets[index],
        );
      }
    },
  );

  test(
    'factory serves only allowlisted assistant text across feature owners',
    () async {
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
      for (final owner in [
        AudioTurnOwner.mainAssistant,
        AudioTurnOwner.continuousTranslation,
        AudioTurnOwner.listeningLesson,
      ]) {
        final service = createVoicePromptService(
          owner: owner,
          httpClient: createLocalCloudinaryAudioClient(),
        );
        await service.speakAndWait(_text);
        await service.speakAndWait('Unlisted dynamic content', locale: 'en-US');
      }
      expect(calls.map((call) => call.method), [
        'playAuthoredAudioAndWait',
        'speakAndWait',
        'playAuthoredAudioAndWait',
        'speakAndWait',
        'playAuthoredAudioAndWait',
        'speakAndWait',
      ]);
      final audioArgs = calls.first.arguments as Map;
      expect(audioArgs['bytes'], isA<Uint8List>());
      expect(audioArgs.containsKey('speed'), false);
      expect(audioArgs['gainDb'], androidAssistantSpeechBoostDb);
    },
  );
}

class _Bundle extends CachingAssetBundle {
  _Bundle({this.mode = ''});
  final String mode;
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  final assetStarted = Completer<void>();
  final assetCompletion = Completer<void>();
  bool blockAsset = false;
  bool blockManifest = false;
  final manifestCompletion = Completer<void>();
  int manifestLoads = 0;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    manifestLoads++;
    if (blockManifest) await manifestCompletion.future;
    if (mode == 'manifest') throw StateError('No manifest');
    final entry = {
      'id': 'AI-001',
      'text': mode == 'text'
          ? 'Different script'
          : mode == 'english'
          ? 'Great!'
          : _text,
      'locale': mode == 'english' ? 'en-US' : 'vi-VN',
      if (mode == 'english') 'lookupLocales': ['en-US', 'vi-VN'],
      'enabled': true,
      if (mode == 'grouped')
        'group': MainAssistantAudioPromptService.challengeCueGroup,
      'asset': _asset,
      'sha256': mode == 'hash' ? 'wrong' : sha256.convert(bytes).toString(),
      'durationSeconds': mode == 'too-long'
          ? 46
          : mode == 'duration'
          ? 0
          : mode == 'long'
          ? 9
          : 5.58,
    };
    return jsonEncode({
      'schemaVersion': 1,
      'enabled': mode != 'disabled',
      'prompts': [entry, if (mode == 'duplicate') entry],
    });
  }

  @override
  Future<ByteData> load(String key) async {
    if (!assetStarted.isCompleted) assetStarted.complete();
    if (blockAsset) await assetCompletion.future;
    if (mode == 'missing') throw StateError('No audio');
    return ByteData.sublistView(bytes);
  }
}

class _CurriculumBundle extends _Bundle {
  _CurriculumBundle({this.extraMode = ''});
  final String extraMode;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key != 'curriculum.json') return super.loadString(key, cache: cache);
    if (extraMode == 'missing') throw StateError('Missing optional pack');
    if (extraMode == 'invalid') return '{';
    return jsonEncode({
      'schemaVersion': 1,
      'enabled': extraMode != 'disabled',
      'prompts': [
        {
          'id': 'LESSON-TEST',
          'text': 'Câu bài học.',
          'locale': 'vi-VN',
          'enabled': true,
          'asset': 'assets/audio/CURRICULUM/test.vi.v1.mp3',
          'sha256': sha256.convert(bytes).toString(),
          'durationSeconds': 14,
        },
      ],
    });
  }
}

class _Delegate
    implements
        VoicePromptService,
        AuthoredAudioVoicePromptService,
        SelectedMediaOutputVoicePromptService,
        PhoneSpeakerVoicePromptService,
        SpeechReadyCuePlayer,
        MainTurnVoicePromptService,
        StyledMediaOutputVoicePromptService {
  final events = <String>[];
  final started = Completer<void>();
  final playback = Completer<void>();
  bool blockPlayback = false;
  bool failPlayback = false;
  Object? playbackError;

  @override
  Future<void> playAuthoredAudioAndWait(
    Uint8List bytes, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) async {
    events.add(
      'audio:${forcePhoneSpeaker
          ? 'phone'
          : forceMediaPlayback
          ? 'selected'
          : 'normal'}',
    );
    if (!started.isCompleted) started.complete();
    final error = playbackError;
    if (error != null) throw error;
    if (failPlayback) throw StateError('Decoder failure');
    if (blockPlayback) await playback.future;
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      speakAndWait(text, locale: locale);
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    events.add('tts:$locale:$text');
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) => speakAndWait(text, locale: locale);
  @override
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  }) => speakAndWait(text, locale: locale);
  @override
  Future<void> speakAndWaitStyled(
    String text, {
    required String locale,
    required double speechRate,
    required double pitch,
  }) async {
    events.add('style:$speechRate:$pitch');
  }

  @override
  Future<void> stop() async {
    events.add('stop');
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
  }

  @override
  Future<void> playSpeechReadyCue() async {
    events.add('cue');
  }

  @override
  Future<String?> beginMainTurn() async {
    events.add('begin');
    return 'main-1';
  }

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    events.add('end:$reason:$turnId');
  }
}
