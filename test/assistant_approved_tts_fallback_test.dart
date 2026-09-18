import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'support/approved_assistant_tts_fallbacks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const extraPacks = [
    'assets/data/curriculum_audio.json',
    'assets/data/homi_gap66_audio.json',
  ];

  test(
    'approved TTS exceptions are exact, unique, and not hiding authored audio',
    () {
      expect(approvedAssistantTtsFallbacks, hasLength(16));
      final entries = [
        for (final path in [
          MainAssistantAudioPromptService.manifestAsset,
          ...extraPacks,
        ])
          ...(jsonDecode(File(path).readAsStringSync())['prompts'] as List),
      ];
      for (final text in approvedAssistantTtsFallbacks) {
        expect(text, isNot(matches(RegExp(r'[$\[\]{}]'))));
        expect(
          entries.where(
            (entry) =>
                entry['text'] == text ||
                (entry['lookupTexts'] as List? ?? []).contains(text),
          ),
          isEmpty,
          reason:
              'Remove the TTS exception once authored audio is added: $text',
        );
      }
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test(
      '$platform approved prompts use native TTS once on the requested route',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const channel = MethodChannel('test_approved_native_tts');
        final calls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final http = MockClient(
          (_) async =>
              throw StateError('TTS fallback must not fetch/upload audio'),
        );
        addTearDown(http.close);
        final prompts = MainAssistantAudioPromptService(
          delegate: const MethodChannelVoicePromptService(channel: channel),
          bundle: _ManifestOnlyBundle(),
          additionalManifestAssets: extraPacks,
          httpClient: http,
        );
        addTearDown(prompts.dispose);
        for (final text in approvedAssistantTtsFallbacks) {
          for (final route in ['selected', 'phone', 'default']) {
            calls.clear();
            if (route == 'selected') {
              await prompts.speakAndWaitOnSelectedMediaOutput(text);
            } else if (route == 'phone') {
              await prompts.speakAndWaitOnPhoneSpeaker(text);
            } else {
              await prompts.speakAndWait(text);
            }
            expect(calls, hasLength(1), reason: '$platform/$route: $text');
            expect(calls.single.method, 'speakAndWait');
            final arguments = calls.single.arguments as Map;
            expect(arguments['text'], text);
            expect(arguments['locale'], 'vi-VN');
            expect(arguments['forcePhoneSpeaker'], route == 'phone');
            expect(arguments['forceMediaPlayback'], route == 'selected');
          }
        }
      },
    );
  }
}

class _ManifestOnlyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (!key.endsWith('.json')) {
      throw StateError('Unexpected audio asset request: $key');
    }
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}
