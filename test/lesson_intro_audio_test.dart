import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'all 109 fresh intros use MP3 without TTS or duplicate hooks on Android and iOS',
    (tester) async {
      final catalog = ListeningContentCatalog.fromJson(
        jsonDecode(
              File('assets/data/listening_lessons.json').readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      final promptsByKey = <String, Map<String, dynamic>>{};
      for (final name in ['listening_common_audio', 'assistant_core_audio']) {
        final manifest =
            jsonDecode(File('assets/data/$name.json').readAsStringSync())
                as Map;
        for (final entry in manifest['prompts'] as List) {
          promptsByKey[entry['key'] as String] = Map<String, dynamic>.from(
            entry as Map,
          );
        }
      }
      final calls = <String>[];
      const channel = MethodChannel('ailingo_voice_prompt');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'playAuthoredAudioAndWait') {
          calls.add(
            sha256
                .convert((call.arguments as Map)['bytes'] as Uint8List)
                .toString(),
          );
        } else if (call.method == 'speakAndWait' || call.method == 'speak') {
          calls.add('TTS: ${(call.arguments as Map)['text']}');
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Keep both platforms in one fake-async zone: the production repository
      // shares a rootBundle index Future across service instances.
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        var total = 0;
        var splitIntros = 0;
        for (final group in catalog.groups) {
          final cards = listeningCatalogs.singleWhere(
            (g) => g.startAge == group.startAge,
          );
          for (final topic in group.topics) {
            for (final lesson in topic.lessons) {
              calls.clear();
              final store = _IntroProgressStore();
              final service = createVoicePromptService(
                owner: AudioTurnOwner.listeningLesson,
              );
              await tester.pumpWidget(
                MaterialApp(
                  theme: buildAppTheme(),
                  home: LessonIntroScreen(
                    language: DisplayLanguage.vietnamese,
                    startAge: group.startAge,
                    endAge: group.endAge,
                    topic: cards.topics[topic.number - 1],
                    topicContent: topic,
                    contentGroup: group,
                    lesson: lesson,
                    progressStore: store,
                    mediaService: _IntroMediaService(),
                    voicePromptService: service,
                    autoAdvance: false,
                  ),
                ),
              );
              for (var step = 0; step < 200 && !store.finished; step++) {
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 5)),
                );
                await tester.pump(const Duration(milliseconds: 16));
              }
              final context = '${platform.name} ${lesson.id}';
              expect(
                store.finished,
                isTrue,
                reason: '$context: intro did not finish',
              );
              final hookKey = ListeningAudioKeys.lessonHook(lesson.id);
              final hasHook = promptsByKey[hookKey]?['enabled'] == true;
              final expectedKeys = hasHook
                  ? [
                      ListeningAudioKeys.lessonIntroLead(lesson.id),
                      hookKey,
                      'assistant.main.start_now.vi',
                    ]
                  : [ListeningAudioKeys.lessonIntro(lesson.id)];
              expect(
                calls,
                expectedKeys
                    .map((key) => promptsByKey[key]!['sha256'])
                    .toList(),
                reason: context,
              );
              if (hasHook) splitIntros++;
              total++;
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await service.dispose();
            }
          }
        }
        expect(total, 109);
        expect(splitIntros, 13);
      }
      debugDefaultTargetPlatformOverride = null;
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _IntroProgressStore extends ListeningProgressStore {
  bool finished = false;
  @override
  Future<int> readLesson(String id) async => 0;
  @override
  Future<int> readCurrentSentence(String id) async => 0;
  @override
  Future<bool> hasOpenedLearningGuide() async => false;
  @override
  Future<bool> hasStartedLessonCore(String id) async => false;
  @override
  Future<ListeningResumeStage> readResumeStage(String id) async =>
      ListeningResumeStage.core;
  @override
  Future<void> markLearningGuideOpened() async {
    finished = true;
  }
}

class _IntroMediaService extends LessonMediaService {
  @override
  Future<void> prepareSelectedLessonOutput() async {}
  @override
  Future<void> stopPlayback() async {}
}
