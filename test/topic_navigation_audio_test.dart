import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/main_assistant_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/topic_navigation_prompts.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final expected = <String, String>{
    MainAssistantAudioKeys.chooseTopic(10): TopicNavigationPrompts.chooseTen,
    MainAssistantAudioKeys.courseRelearnTopic:
        TopicNavigationPrompts.courseRelearn,
    MainAssistantAudioKeys.chooseTenTopicRange:
        TopicNavigationPrompts.chooseTenRange,
  };
  final manifestFile = File('assets/data/assistant_core_audio.json');
  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
  final prompts = (manifest['prompts'] as List).cast<Map<String, dynamic>>();

  test(
    'imported recordings and updated pack index preserve integrity',
    () async {
      final index =
          jsonDecode(
                File('assets/data/audio_pack_index.json').readAsStringSync(),
              )
              as Map;
      final pack = (index['packs'] as List).cast<Map>().singleWhere(
        (e) => e['pack'] == 'assistant-core',
      );
      expect(
        pack['manifestSha256'],
        sha256.convert(manifestFile.readAsBytesSync()).toString(),
      );
      expect(pack['version'], manifest['version']);
      expect(pack['audioCount'], prompts.length);
      expect(
        pack['sizeBytes'],
        prompts.fold<int>(0, (sum, e) => sum + (e['sizeBytes'] as int)),
      );
      for (final entry in expected.entries) {
        final prompt = prompts.singleWhere((p) => p['key'] == entry.key);
        expect(prompt['enabled'], isTrue);
        expect(prompt['text'], entry.value);
        expect(
          prompt['textHash'],
          sha256.convert(utf8.encode(entry.value)).toString(),
        );
        expect(prompt['source'], 'user-provided');
        expect(prompt['durationSeconds'], inExclusiveRange(0, 45));
        final bytes = File(prompt['asset'] as String).readAsBytesSync();
        expect(bytes.length, prompt['sizeBytes']);
        expect(sha256.convert(bytes).toString(), prompt['sha256']);
        final bundled = await rootBundle.load(prompt['asset'] as String);
        expect(
          sha256
              .convert(
                bundled.buffer.asUint8List(
                  bundled.offsetInBytes,
                  bundled.lengthInBytes,
                ),
              )
              .toString(),
          prompt['sha256'],
        );
      }
    },
  );

  test(
    'MAIN and lesson outputs play the supplied bytes, including unkeyed retry',
    () async {
      const channel = MethodChannel('ailingo_voice_prompt');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final loudness =
          jsonDecode(
                File('assets/data/audio_loudness.json').readAsStringSync(),
              )['gainDb']
              as Map;
      for (final owner in [
        AudioTurnOwner.mainAssistant,
        AudioTurnOwner.listeningLesson,
      ]) {
        final service = createVoicePromptService(owner: owner);
        addTearDown(service.dispose);
        for (final entry in expected.entries) {
          final prompt = prompts.singleWhere((p) => p['key'] == entry.key);
          for (final route in ['keyed', 'unkeyed', 'selected', 'phone']) {
            calls.clear();
            switch (route) {
              case 'keyed':
                await (service as KeyedVoicePromptService)
                    .speakAndWaitWithAudioKey(entry.key, entry.value);
              case 'unkeyed':
                await service.speakAndWait(entry.value);
              case 'selected':
                await (service as KeyedSelectedMediaOutputVoicePromptService)
                    .speakAndWaitOnSelectedMediaOutputWithAudioKey(
                      entry.key,
                      entry.value,
                    );
              case 'phone':
                await (service as PhoneSpeakerVoicePromptService)
                    .speakAndWaitOnPhoneSpeaker(entry.value);
            }
            expect(
              calls,
              hasLength(1),
              reason: '${owner.name} ${entry.key} $route',
            );
            expect(calls.single.method, 'playAuthoredAudioAndWait');
            final args = calls.single.arguments as Map;
            expect(
              sha256.convert(args['bytes'] as Uint8List).toString(),
              prompt['sha256'],
            );
            expect(args['gainDb'], loudness[prompt['asset']]);
            expect(args['forceMediaPlayback'], route == 'selected');
            expect(args['forcePhoneSpeaker'], route == 'phone');
          }
        }
      }
    },
  );

  test(
    'all age groups use recordings for selection, both invalid choices and silence',
    () async {
      for (final age in [3, 6, 8, 11, 13]) {
        final flow = MainVoiceAssistantFlow(childAge: age);
        final numbers = List.generate(10, (index) => index + 1);
        final opening = flow.beginTopicSelection(
          childAge: age,
          topicNumbers: numbers,
          completedTopicNumbers: [],
        );
        expect(opening, TopicNavigationPrompts.chooseTen);
        expect(
          flow.currentPromptAudioKey,
          MainAssistantAudioKeys.chooseTopic(10),
        );
        expect(
          flow.silenceRetryAudioKey,
          MainAssistantAudioKeys.chooseTopic(10),
        );
        final invalid = await flow.handle('Chủ đề 11');
        expect(invalid.promptText, TopicNavigationPrompts.chooseTenRange);
        expect(
          flow.audioKeyForPrompt(invalid.promptText),
          MainAssistantAudioKeys.chooseTenTopicRange,
        );
        expect(flow.canHandle(TopicNavigationPrompts.chooseTenRange), isFalse);
        final echo = await flow.handle(TopicNavigationPrompts.chooseTenRange);
        expect(echo.navigationBeforePrompt, isNull);
        expect(echo.navigationAfterPrompt, isNull);
        expect(echo.continueListening, isTrue);
        expect(
          flow.beginCourseRelearnTopicSelection(
            childAge: age,
            topicNumbers: numbers,
          ),
          TopicNavigationPrompts.courseRelearn,
        );
        expect(
          flow.currentPromptAudioKey,
          MainAssistantAudioKeys.courseRelearnTopic,
        );
        expect(
          flow.silenceRetryAudioKey,
          MainAssistantAudioKeys.courseRelearnTopic,
        );
        final invalidReplay = await flow.handle('Chủ đề 11');
        expect(invalidReplay.promptText, TopicNavigationPrompts.chooseTenRange);
        expect(
          flow.audioKeyForPrompt(invalidReplay.promptText),
          MainAssistantAudioKeys.chooseTenTopicRange,
        );
        expect(flow.canHandle(TopicNavigationPrompts.chooseTenRange), isFalse);
        final replayEcho = await flow.handle(
          TopicNavigationPrompts.chooseTenRange,
        );
        expect(replayEcho.navigationBeforePrompt, isNull);
        expect(replayEcho.navigationAfterPrompt, isNull);
        expect(replayEcho.continueListening, isTrue);
      }
    },
  );

  test('a restricted replay menu never advertises all ten choices', () async {
    final flow = MainVoiceAssistantFlow(childAge: 3);
    flow.beginCourseRelearnTopicSelection(childAge: 3, topicNumbers: [2, 5]);
    final invalid = await flow.handle('Chủ đề 1');
    expect(invalid.promptText, 'Bạn chọn Chủ đề 2, 5 nhé.');
    expect(flow.audioKeyForPrompt(invalid.promptText), isNull);
  });
}
