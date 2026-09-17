// Diagnostic only. No audio synthesis, network, or production mutations.
// Run: flutter test tool/audit_homi_utterances_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/authored_question_selector.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/v4_completion_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_fallback_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/homi_fallback_catalog.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/controlled_speech_lexicon.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_flow_v3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'enumerate real domain outputs without playing or generating audio',
    () async {
      final catalog = ListeningContentCatalog.fromJson(
        jsonDecode(
              File('assets/data/listening_lessons.json').readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      final rows = <String, Map<String, Object?>>{};
      const mainSource =
          'lib/features/voice_navigation/application/main_voice_assistant_flow.dart';
      const guideSource =
          'lib/features/listening/domain/lesson_guide_flow.dart';
      void add(
        String text,
        String family,
        String source, {
        String scope = 'current',
        String locale = 'vi-VN',
        String? context,
      }) {
        if (text.trim().isEmpty) return;
        final key = '$scope|$family|$locale|${text.trim()}';
        rows.putIfAbsent(
          key,
          () => {
            'text': text.trim(),
            'locale': locale,
            'scope': scope,
            'family': family,
            'source': source,
            'exampleContext': context,
            'evidence': 'executed_domain_function',
          },
        );
      }

      void turn(MainVoiceAssistantTurn result, String scope, String context) {
        // Controller plays promptSequence INSTEAD OF the display-only joined text.
        final sequence = result.promptSequence.isNotEmpty
            ? result.promptSequence
            : [MainVoiceAssistantUtterance(result.promptText)];
        for (final item in sequence) {
          add(
            item.text,
            'main_flow',
            mainSource,
            scope: scope,
            locale: item.locale,
            context: context,
          );
        }
      }

      MainVoiceAssistantFlow flow([int? age]) => MainVoiceAssistantFlow(
        childAge: age,
        contentLoader: () async => catalog,
        vocabularyLoader: () async => [],
      );
      final smallInputs = <String>{
        'xyz',
        'giúp mình',
        'có',
        'không',
        'học lại',
        'học tiếp',
        'dừng lại',
        'học cái khác',
        'học chủ đề',
        'dịch sang tiếng Anh',
        'học từ vựng',
        for (var n = 0; n <= 16; n++) '$n',
        for (var n = 0; n <= 10; n++) 'chủ đề $n',
        '99',
        'Level 99',
        'học bài 99',
        'tiếp tục bài tiếp theo',
        'Bạn muốn học lại chủ đề này không? Nói có hoặc không',
      }.toList();
      var transitions = 0;
      var scenarios = 0;
      final reached = <String, Set<String>>{};
      // Rebuild each path so progress/fallback attempts cannot leak between probes.
      // Depth is bounded; this is a reproducible branch audit, not a proof over
      // every possible utterance, corrupt state, or arbitrarily long dialogue.
      Future<void> explore(
        MainVoiceAssistantFlow Function() make,
        String Function(MainVoiceAssistantFlow) begin,
        String label, {
        String scope = 'current',
        bool fullInputs = false,
      }) async {
        scenarios++;
        final inputs = fullInputs
            ? {
                ...smallInputs,
                ...HomiFallbackCatalog.childPhrasesByIntent.values.expand(
                  (x) => x,
                ),
                ...ControlledSpeechLexicon.rules.expand((r) => r.phrases),
              }.toList()
            : smallInputs;
        final queue = <List<String>>[[]];
        final seen = <String>{};
        final scheduled = <String>{};
        for (var index = 0; index < queue.length; index++) {
          final path = queue[index];
          final probe = make();
          final opening = begin(probe);
          add(
            opening,
            'main_flow',
            mainSource,
            scope: scope,
            context: '$label: begin',
          );
          MainVoiceAssistantTurn? previous;
          for (final input in path) {
            previous = await probe.handle(input);
          }
          reached.putIfAbsent(scope, () => {}).add(probe.stage.name);
          final signature =
              '${probe.stage.name}|${previous?.promptText ?? opening}';
          if (!seen.add(signature) ||
              path.length >= 4 ||
              (previous != null && !previous.continueListening)) {
            continue;
          }
          // Echo of the actual previous prompt is a separate runtime branch.
          for (final input in {...inputs, previous?.promptText ?? opening}) {
            final instance = make();
            begin(instance);
            for (final step in path) {
              await instance.handle(step);
            }
            final before = instance.stage.name;
            final result = await instance.handle(input);
            transitions++;
            turn(
              result,
              scope,
              '$label: ${[...path, input].join(' → ')} [$before]',
            );
            reached.putIfAbsent(scope, () => {}).add(instance.stage.name);
            if (result.continueListening && path.length < 3) {
              final nextKey = '${instance.stage.name}|${result.promptText}';
              if (!seen.contains(nextKey) && scheduled.add(nextKey)) {
                queue.add([...path, input]);
              }
            }
          }
        }
      }

      for (final age in <int?>[null, 3, 6, 8, 11, 13]) {
        await explore(
          () => flow(age),
          (f) => f.begin(),
          'main age=$age',
          fullInputs: true,
        );
      }
      await explore(
        flow,
        (f) => f.beginOtherLearning(),
        'other learning',
        fullInputs: true,
      );
      await explore(
        flow,
        (f) => f.beginAfterTranslationStop(),
        'after translation',
        fullInputs: true,
      );
      for (final kind in ActiveLearningModuleKind.values) {
        await explore(
          () => flow(6),
          (f) => f.beginActiveLearning(kind: kind),
          'active ${kind.name}',
          fullInputs: true,
        );
      }
      for (final group in catalog.groups) {
        for (final level in group.levels) {
          for (final completed in [<int>[], level.topicNumbers]) {
            for (final announce in [false, true]) {
              await explore(
                () => flow(group.startAge),
                (f) => f.beginLevelTopicSelection(
                  childAge: group.startAge,
                  levelNumber: level.number,
                  topicNumbers: level.topicNumbers,
                  completedTopicNumbers: completed,
                  announceLevel: announce,
                ),
                'age=${group.startAge} level=${level.number} completed=$completed announce=$announce',
              );
            }
          }
        }
        await explore(
          () => flow(group.startAge),
          (f) => f.beginCourseRelearnLevelSelection(
            childAge: group.startAge,
            levelNumbers: group.levels.map((x) => x.number).toList(),
          ),
          'course relearn age=${group.startAge}',
        );
        for (final topic in group.topics) {
          // Public compatibility entry point: wired through app/controller but
          // its screen callback has no invocation in the present catalog flow.
          for (var mask = 0; mask < (1 << topic.lessons.length); mask++) {
            final completed = [
              for (var i = 0; i < topic.lessons.length; i++)
                if (mask & (1 << i) != 0) topic.lessons[i].number,
            ];
            await explore(
              () => flow(group.startAge),
              (f) => f.beginLessonSelectionForTopic(
                childAge: group.startAge,
                topicNumber: topic.number,
                topicContent: topic,
                completedLessonNumbers: completed,
              ),
              '${topic.id} completed=$completed',
              scope: 'compatibility',
            );
          }
          for (final lesson in topic.lessons) {
            expect(lesson.usesV4Flow, true, reason: lesson.id);
            expect(lesson.challengeBank.length, lesson.sentences.length);
            for (final question in lesson.challengeBank) {
              expect(
                const AuthoredQuestionSelector()
                    .selectSingleChallenge(
                      lesson.challengeBank,
                      weakTargetIds: [question.targetId],
                    )
                    ?.id,
                question.id,
                reason: 'Every counted Challenge must actually be selectable',
              );
            }
            for (final kind in LessonEntryGuideKind.values) {
              add(
                LessonGuideFlowV2.entry(
                  lessonCode: lesson.code,
                  lessonTitle: lesson.titleEn,
                  kind: kind,
                ).text,
                'legacy_guide',
                guideSource,
                scope: 'compatibility',
                context: lesson.id,
              );
            }
            add(
              LessonGuideFlowV2.ending(
                lessonCode: lesson.code,
                lessonTitleVi: lesson.titleVi,
              ).text,
              'legacy_guide',
              guideSource,
              scope: 'compatibility',
              context: lesson.id,
            );
            if (lesson.number < topic.lessons.length) {
              add(
                v4CompletionPrompt(
                  V4CompletionStage.lessonEnd,
                  currentLesson: lesson.number,
                  nextLesson: lesson.number + 1,
                ),
                'completion',
                'lib/features/listening/domain/v4_completion_flow.dart',
              );
            }
            if (lesson.songTitle != null) {
              add(v4SongStartCue(lesson.songTitle!), 'song_start', guideSource);
              add(
                v4SongPrealert(lesson.songTitle!),
                'song_prealert',
                guideSource,
                scope: 'catalog_only',
              );
            }
          }
          add(
            v4CompletionPrompt(
              V4CompletionStage.topicEnd,
              topicNumber: topic.number,
            ),
            'completion',
            'lib/features/listening/domain/v4_completion_flow.dart',
          );
        }
        for (final level in group.levels.skip(1)) {
          add(
            v4CompletionPrompt(
              V4CompletionStage.nextLevel,
              nextLevel: level.number,
            ),
            'completion',
            'lib/features/listening/domain/v4_completion_flow.dart',
          );
        }
      }
      for (final stage in [
        V4CompletionStage.topicEndOneRemaining,
        V4CompletionStage.courseRelearnLevel,
      ]) {
        add(
          v4CompletionPrompt(stage),
          'completion',
          'lib/features/listening/domain/v4_completion_flow.dart',
        );
      }
      for (final age in [3, 6, 8, 11, 13]) {
        for (final kind in LessonFeedbackKind.values) {
          for (final text in LessonAgeFeedbackLibrary.messages(
            age: age,
            kind: kind,
          )) {
            add(
              text,
              'age_feedback',
              guideSource,
              context: 'age=$age ${kind.name}',
            );
          }
        }
      }
      for (final prompt in LessonGuideFlowV2.coreSpeakCues) {
        add(
          prompt.text,
          'core_speak_cue',
          guideSource,
          context: prompt.audioCode,
        );
      }
      for (final prompt in VocabularyFlowV3.fixedPrompts) {
        add(
          prompt.text,
          'vocabulary_guidance',
          'lib/features/vocabulary/domain/vocabulary_flow_v3.dart',
        );
      }
      for (final text in [
        VocabularyFlowV3.finishActiveGroupFirst,
        VocabularyFlowV3.pauseAfterNoResponse,
      ]) {
        add(
          text,
          'vocabulary_guidance',
          'lib/features/vocabulary/domain/vocabulary_flow_v3.dart',
        );
      }
      for (final text in [
        MainVoiceAssistantFlow.noSpeechRetryPrompt,
        MainVoiceAssistantFlow.noSpeechExitPrompt,
      ]) {
        add(text, 'main_silence', mainSource);
      }
      for (final id in ['SIL-003', 'SIL-004']) {
        add(
          HomiFallbackCatalog.silencePromptById[id]!,
          'translation_silence',
          'lib/app/ai_speaking_app.dart',
          context: id,
        );
      }
      for (final input
          in HomiFallbackCatalog.childPhrasesByIntent.values.expand((x) => x)) {
        final instance = MainSpeakingFallbackFlow();
        final first = instance.handle(input);
        if (first?.promptText != null) {
          add(
            first!.promptText!,
            'translation_control',
            'lib/features/voice_navigation/application/main_speaking_fallback_flow.dart',
          );
        }
        final second = instance.handle('xyz');
        if (second?.promptText != null) {
          add(
            second!.promptText!,
            'translation_control',
            'lib/features/voice_navigation/application/main_speaking_fallback_flow.dart',
          );
        }
      }
      // Exercise the real error branches without any failed network request.
      for (final broken in [false, true]) {
        final emptyTopic = ListeningContentCatalog.fromJson({
          'groups': [
            {
              'startAge': 3,
              'endAge': 5,
              'topics': [
                {'number': 1, 'lessons': <Object>[]},
              ],
            },
          ],
        });
        final instance = MainVoiceAssistantFlow(
          childAge: 3,
          contentLoader: () async {
            if (broken) throw StateError('Simulated catalog read failure');
            return emptyTopic;
          },
          vocabularyLoader: () async => [],
        );
        instance.beginLevelTopicSelection(
          childAge: 3,
          levelNumber: 1,
          topicNumbers: [1, 2, 3],
          completedTopicNumbers: [],
          announceLevel: false,
        );
        turn(
          await instance.handle('chủ đề 1'),
          'current',
          'catalog failure=$broken',
        );
        scenarios++;
        transitions++;
      }
      // Catalog membership alone is not proof of runtime speech.
      for (final text in [
        ...HomiFallbackCatalog.assistantPromptById.values,
        ...HomiFallbackCatalog.silencePromptById.values,
        ...HomiFallbackCatalog.fallbackPolicyById.values.expand(
          (p) => [p.firstPrompt, p.secondPrompt],
        ),
      ]) {
        if (!text.contains('{')) {
          add(
            text,
            'assistant_catalog',
            'lib/features/voice_navigation/domain/homi_fallback_catalog.dart',
            scope: 'catalog_only',
          );
        }
      }
      final output = File(const String.fromEnvironment(
        'HOMI_AUDIT_OUTPUT',
        defaultValue: 'deliverables/homi-runtime-domain-audit.json',
      ));
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'scenarios': scenarios, 'transitions': transitions, 'maxDialogueProbeDepth': 4, 'reachedStages': reached.map((key, value) => MapEntry(key, value.toList()..sort())), 'rows': rows.values.toList()})}\n',
      );
      expect(transitions, greaterThan(1000));
      expect(rows.values.where((r) => r['scope'] == 'current'), isNotEmpty);
      // ignore: avoid_print
      print(
        'HOMI domain audit: $scenarios contexts, $transitions transitions, ${rows.length} grouped outputs.',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
