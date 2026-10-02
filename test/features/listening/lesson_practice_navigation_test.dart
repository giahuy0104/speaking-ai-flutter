import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/learning_audio_dependencies.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_guide_audio_library.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_completion_choice_recognizer.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_challenge_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_practice_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'finishing Topic 1 continues the remaining Topic at its unfinished lesson',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _usePhoneSurface(tester);
      final first = _v4Lesson();
      final alreadyCompleted = _v4Lesson(number: 2);
      final unfinished = _v4Lesson(
        number: 3,
        sentences: const [
          ListeningSentenceContent(
            id: 'topic-two-sentence-one',
            number: 1,
            english: 'Good morning.',
            vietnamese: 'Chào buổi sáng.',
          ),
          ListeningSentenceContent(
            id: 'topic-two-sentence-two',
            number: 2,
            english: 'Good night.',
            vietnamese: 'Chúc ngủ ngon.',
          ),
        ],
      );
      final firstTopic = ListeningTopicContent(
        id: 'topic-one',
        number: 1,
        titleVi: 'Chủ đề 1',
        titleEn: 'Topic 1',
        levelNumber: 1,
        lessons: [first],
      );
      final secondTopic = ListeningTopicContent(
        id: 'topic-two',
        number: 2,
        titleVi: 'Chủ đề 2',
        titleEn: 'Topic 2',
        levelNumber: 1,
        lessons: [alreadyCompleted, unfinished],
      );
      const level = ListeningLevelContent(
        id: 'level-one',
        number: 1,
        titleVi: 'Level 1',
        topicNumbers: [1, 2],
      );
      final group = ListeningContentAgeGroup(
        startAge: 3,
        endAge: 5,
        topics: [firstTopic, secondTopic],
        levels: [level],
      );
      final store = _TopicTransitionProgressStore()
        ..progress.addAll({first.id: 1, alreadyCompleted.id: 1})
        ..cursors[unfinished.id] = 1
        ..coreStarted = true
        ..stages[alreadyCompleted.id] = ListeningResumeStage.completed
        ..pendingCompletionChoice =
            ListeningPendingChoiceStage.topicEndOneRemaining;
      store.completedV4LessonActivities.addAll([first.id, alreadyCompleted.id]);
      final voice = _KeyedRecordingVoicePromptService();
      final media = _SilentMediaService();
      await tester.pumpWidget(
        _subject(
          first,
          store,
          const Key('topic-one-completion'),
          topicContent: firstTopic,
          contentGroup: group,
          levelContent: level,
          voicePromptService: voice,
          mediaService: media,
          initialResumeStage: ListeningResumeStage.waitingForChoice,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('v4-choice-nextTopic')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final practice = tester.widget<LessonPracticeScreen>(
        find.byType(LessonPracticeScreen),
      );
      expect(practice.topicContent?.number, 2);
      expect(practice.lesson.id, unfinished.id);
      expect(find.byKey(const ValueKey('v4-choice-nextTopic')), findsNothing);
      expect(
        voice.spoken.join(' '),
        contains('Mình học tiếp bài V4 lesson nhé.'),
      );
      expect(store.cursors[unfinished.id], 1);
      expect(media.startedSentenceIds.last, unfinished.sentences[1].id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  for (final choice in <(String, int?)>[
    ('Chủ đề 2', 2),
    ('Chủ đề số 2', 2),
    ('Chủ đề 3', 3),
    ('Chủ đề 1', null),
    ('Chủ đề 4', null),
  ]) {
    testWidgets(
      'iOS completion validates spoken ${choice.$1} when Topics 2 and 3 remain',
      (tester) async {
        final transcript = choice.$1;
        SharedPreferences.setMockInitialValues({});
        await _usePhoneSurface(tester);
        final first = _v4Lesson();
        final second = _v4Lesson(number: 2);
        final third = _v4Lesson(number: 3);
        final topics = <ListeningTopicContent>[
          ListeningTopicContent(
            id: 'topic-one',
            number: 1,
            titleVi: 'Chủ đề 1',
            titleEn: 'Topic 1',
            levelNumber: 1,
            lessons: [first],
          ),
          ListeningTopicContent(
            id: 'topic-two',
            number: 2,
            titleVi: 'Chủ đề 2',
            titleEn: 'Topic 2',
            levelNumber: 1,
            lessons: [second],
          ),
          ListeningTopicContent(
            id: 'topic-three',
            number: 3,
            titleVi: 'Chủ đề 3',
            titleEn: 'Topic 3',
            levelNumber: 1,
            lessons: [third],
          ),
        ];
        const level = ListeningLevelContent(
          id: 'level-one',
          number: 1,
          titleVi: 'Level 1',
          topicNumbers: [1, 2, 3],
        );
        final group = ListeningContentAgeGroup(
          startAge: 3,
          endAge: 5,
          topics: topics,
          levels: [level],
        );
        final store = _TopicTransitionProgressStore()
          ..progress[first.id] = 1
          ..coreStarted = true
          ..pendingCompletionChoice = ListeningPendingChoiceStage.topicEnd;
        store.completedV4LessonActivities.add(first.id);
        final speech = _IosCompletionCommandSpeechInput(transcript);
        addTearDown(speech.dispose);
        final media = _SilentMediaService();
        await tester.pumpWidget(
          _subject(
            first,
            store,
            Key('ios-explicit-$transcript'),
            topicContent: topics.first,
            contentGroup: group,
            levelContent: level,
            controller: _LearningAudioDependencies(speech),
            voicePromptService: _SilentVoicePromptService(),
            mediaService: media,
            initialResumeStage: ListeningResumeStage.waitingForChoice,
          ),
        );
        await tester.pumpAndSettle();
        expect(speech.commands.commandStarts, 1);
        speech.commands.partial.add(transcript);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 701));
        await tester.pump();

        if (choice.$2 == null) {
          expect(find.byType(LessonIntroScreen), findsNothing);
          expect(
            find.byKey(const ValueKey('v4-choice-nextTopic')),
            findsOneWidget,
          );
          expect(
            store.pendingCompletionChoice,
            ListeningPendingChoiceStage.topicEnd,
          );
          await tester.tap(find.byKey(const ValueKey('v4-choice-stop')));
          await tester.pumpAndSettle();
        } else {
          final intro = tester.widget<LessonIntroScreen>(
            find.byType(LessonIntroScreen),
          );
          expect(intro.topicContent?.number, choice.$2);
          expect(intro.lesson.id, choice.$2 == 2 ? second.id : third.id);
          expect(store.pendingCompletionChoice, isNull);
        }
        expect(media.startRecordingCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  for (final command in [
    ActiveLearningCommand.nextItem,
    ActiveLearningCommand.previousItem,
  ]) {
    testWidgets(
      'late ${command.name} progress save cannot change a resumed sentence',
      (tester) async {
        await _usePhoneSurface(tester);
        final registry = ActiveLearningModuleRegistry();
        addTearDown(registry.dispose);
        final store = _GatedNavigationProgressStore(command);
        final lesson = _lessonWithSentences(3);
        final media = _SilentMediaService();
        await tester.pumpWidget(
          ActiveLearningModuleScope(
            registry: registry,
            child: _subject(
              lesson,
              store,
              const Key('late-navigation-save'),
              mediaService: media,
              voicePromptService: _SilentVoicePromptService(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sentence 2'), findsOneWidget);

        expect(
          (await registry.interruptAndExecute(command)).wasHandled,
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(store.savePending, isTrue);
        expect(await registry.pauseForMainAssistant(), isTrue);
        expect(
          (await registry.execute(
            ActiveLearningCommand.replayCurrent,
          )).wasHandled,
          isTrue,
        );
        await tester.pumpAndSettle();
        final resumedAudio = List<Uri>.of(media.playedUris);
        expect(resumedAudio.last, lesson.sentences[1].audioUri);

        store.releaseSave();
        await tester.pumpAndSettle();
        expect(find.text('Sentence 2'), findsOneWidget);
        expect(media.playedUris, resumedAudio);
        expect(store.currentSentence, 1);
        expect(media.recording, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets(
    'MAIN replay during initial cursor loading waits for the restored sentence',
    (tester) async {
      await _usePhoneSurface(tester);
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final store = _GatedInitialCursorStore();
      final lesson = _lessonWithSentences(3);
      final media = _SilentMediaService();
      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: _subject(
            lesson,
            store,
            const Key('main-before-restored-cursor'),
            mediaService: media,
            voicePromptService: _SilentVoicePromptService(),
          ),
        ),
      );
      await tester.pump();
      expect(await registry.pauseForMainAssistant(), isTrue);
      expect(
        (await registry.execute(
          ActiveLearningCommand.replayCurrent,
        )).wasHandled,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(media.playedUris, isEmpty);
      // Repeated input while storage is still loading must start one fresh turn.
      expect(
        (await registry.execute(
          ActiveLearningCommand.replayCurrent,
        )).wasHandled,
        isTrue,
      );
      store.releaseRead();
      await tester.pumpAndSettle();
      expect(find.text('Sentence 2'), findsOneWidget);
      expect(media.playedUris, [lesson.sentences[1].audioUri]);
      expect(store.currentSentence, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  for (final lateFailure in [false, true]) {
    testWidgets(
      'iOS pending completion start cannot cancel newer MAIN (lateFailure=$lateFailure)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await _usePhoneSurface(tester);
        final registry = ActiveLearningModuleRegistry();
        addTearDown(registry.dispose);
        final store = _MemoryProgressStore()
          ..completedSentences = 1
          ..challengeProcessed = true
          ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd
          ..resumeStage = ListeningResumeStage.waitingForChoice;
        final gate = Completer<void>();
        final speech = _IosCompletionCommandSpeechInput('Học lại')
          ..firstStartGate = gate
          ..firstStartFails = lateFailure;
        addTearDown(speech.dispose);
        await tester.pumpWidget(
          ActiveLearningModuleScope(
            registry: registry,
            child: _subject(
              _v4Lesson(),
              store,
              const Key('ios-pending-choice'),
              mediaService: _SilentMediaService(),
              voicePromptService: _SilentVoicePromptService(),
              controller: _LearningAudioDependencies(speech),
              initialResumeStage: ListeningResumeStage.waitingForChoice,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(speech.commands.commandStarts, 1);
        expect(await registry.pauseForMainAssistant(), isTrue);
        expect(speech.commands.cancels, 1);
        await speech.startCommandRecognition(); // New owner: MAIN.
        gate.complete();
        await tester.pumpAndSettle();
        expect(speech.commands.commandStarts, 2);
        expect(speech.commands.cancels, 1);
        expect(find.byType(LessonIntroScreen), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
  testWidgets(
    'iOS completion final received during native start stops choice once',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _usePhoneSurface(tester);
      final store = _MemoryProgressStore()
        ..completedSentences = 1
        ..challengeProcessed = true
        ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd
        ..resumeStage = ListeningResumeStage.waitingForChoice;
      final gate = Completer<void>();
      final speech = _IosCompletionCommandSpeechInput('Dừng lại')
        ..firstStartGate = gate;
      addTearDown(speech.dispose);
      await tester.pumpWidget(
        _subject(
          _v4Lesson(),
          store,
          const Key('ios-early-final-choice'),
          mediaService: _SilentMediaService(),
          voicePromptService: _SilentVoicePromptService(),
          controller: _LearningAudioDependencies(speech),
          initialResumeStage: ListeningResumeStage.waitingForChoice,
        ),
      );
      await tester.pumpAndSettle();
      expect(speech.commands.commandStarts, 1);
      speech.commands.done.add(null);
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(speech.commands.stops, 1);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'iOS completion keeps an early partial and ends after silence without more native events',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _usePhoneSurface(tester);
      final lesson = _v4Lesson();
      final store = _MemoryProgressStore()
        ..completedSentences = 1
        ..challengeProcessed = true
        ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd
        ..resumeStage = ListeningResumeStage.waitingForChoice;
      final gate = Completer<void>();
      final speech = _IosCompletionCommandSpeechInput('Bài 2')
        ..firstStartGate = gate;
      addTearDown(speech.dispose);
      final media = _SilentMediaService();
      await tester.pumpWidget(
        _subject(
          lesson,
          store,
          const Key('ios-early-partial-choice'),
          mediaService: media,
          voicePromptService: _SilentVoicePromptService(),
          controller: _LearningAudioDependencies(speech),
          topicContent: ListeningTopicContent(
            id: 'topic-1',
            number: 1,
            titleVi: 'Chủ đề 1',
            titleEn: 'Topic 1',
            lessons: [lesson, _v4Lesson(number: 2)],
          ),
          initialResumeStage: ListeningResumeStage.waitingForChoice,
        ),
      );
      await tester.pumpAndSettle();
      expect(speech.commands.commandStarts, 1);
      // SpeechAnalyzer can publish the child's entire answer before the native
      // start reply, then stay silent until Dart requests finalization.
      speech.commands.partial.add('Bài 2');
      await tester.pump();
      expect(speech.commands.stops, 0);
      gate.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 701));
      await tester.pump();
      expect(speech.commands.stops, 1);
      final intro = tester.widget<LessonIntroScreen>(
        find.byType(LessonIntroScreen),
      );
      expect(intro.lesson.number, 2);
      expect(store.pendingCompletionChoice, isNull);
      expect(media.startRecordingCount, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'iOS old completion result cannot navigate after MAIN resumes a new choice',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _usePhoneSurface(tester);
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final store = _MemoryProgressStore()
        ..completedSentences = 1
        ..challengeProcessed = true
        ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd
        ..resumeStage = ListeningResumeStage.waitingForChoice;
      final gate = Completer<void>();
      final speech = _IosCompletionCommandSpeechInput('Học lại')
        ..firstStopGate = gate;
      addTearDown(speech.dispose);
      final media = _SilentMediaService();
      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: _subject(
            _v4Lesson(),
            store,
            const Key('ios-stale-choice'),
            mediaService: media,
            voicePromptService: _SilentVoicePromptService(),
            controller: _LearningAudioDependencies(speech),
            initialResumeStage: ListeningResumeStage.waitingForChoice,
          ),
        ),
      );
      await tester.pumpAndSettle();
      speech.commands.partial.add('Học lại');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 701));
      await tester.pump();
      expect(speech.commands.stops, 1);
      expect(await registry.pauseForMainAssistant(), isTrue);
      await tester.pump();
      final resume = registry.execute(ActiveLearningCommand.resume);
      await tester.pumpAndSettle();
      expect((await resume).wasHandled, isTrue);
      expect(speech.commands.commandStarts, 2);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LessonIntroScreen), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('v4-choice-stop')),
        findsOneWidget,
      );
      expect(
        store.pendingCompletionChoice,
        ListeningPendingChoiceStage.lessonEnd,
      );
      expect(media.startRecordingCount, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'iOS completion permission failure leaves touch choices without recorder fallback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _usePhoneSurface(tester);
      final store = _MemoryProgressStore()
        ..completedSentences = 1
        ..challengeProcessed = true
        ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd
        ..resumeStage = ListeningResumeStage.waitingForChoice;
      final speech = _IosCompletionCommandSpeechInput('Dừng lại')
        ..failStart = true;
      addTearDown(speech.dispose);
      final media = _SilentMediaService();
      await tester.pumpWidget(
        _subject(
          _v4Lesson(),
          store,
          const Key('ios-failed-choice'),
          mediaService: media,
          voicePromptService: _SilentVoicePromptService(),
          controller: _LearningAudioDependencies(speech),
          initialResumeStage: ListeningResumeStage.waitingForChoice,
        ),
      );
      await tester.pumpAndSettle();
      expect(speech.commands.commandStarts, 1);
      expect(media.startRecordingCount, 0);
      expect(
        find.byKey(const ValueKey<String>('v4-choice-stop')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('v4-choice-stop')));
      await tester.pumpAndSettle();
      expect(store.pendingCompletionChoice, isNull);
      expect(store.resumeStage, ListeningResumeStage.completed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final choice in [('Học lại', 1, true), ('Bài 2', 2, false)]) {
    testWidgets(
      'iOS foreground completion "$choice" uses Apple Speech without a second recorder',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await _usePhoneSurface(tester);
        final lesson = _v4Lesson();
        final store = _MemoryProgressStore()
          ..completedSentences = 1
          ..challengeProcessed = true
          ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd
          ..resumeStage = ListeningResumeStage.waitingForChoice;
        final speech = _IosCompletionCommandSpeechInput(choice.$1);
        addTearDown(speech.dispose);
        final media = _SilentMediaService();
        final prompts = _ReadyCueVoicePromptService(() {
          expect(
            speech.commands.commandStarts,
            0,
            reason: 'iOS drains ting before opening Apple Speech',
          );
          expect(media.selectedOutputPreparationCount, greaterThan(0));
        });
        await tester.pumpWidget(
          _subject(
            lesson,
            store,
            Key('ios-choice-${choice.$2}'),
            mediaService: media,
            voicePromptService: prompts,
            controller: _LearningAudioDependencies(speech),
            topicContent: ListeningTopicContent(
              id: 'topic-1',
              number: 1,
              titleVi: 'Chủ đề 1',
              titleEn: 'Topic 1',
              lessons: [lesson, _v4Lesson(number: 2)],
            ),
            initialResumeStage: ListeningResumeStage.waitingForChoice,
          ),
        );
        await tester.pumpAndSettle();
        expect(prompts.readyCues, 1);
        expect(speech.commands.commandStarts, 1);
        expect(media.nativeHandoffCount, 1);
        expect(media.startRecordingCount, 0);
        expect(find.text('Thả để lưu bản ghi'), findsNothing);
        expect(find.text('Nhấn và giữ để ghi âm'), findsOneWidget);
        speech.commands.partial.add(choice.$1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 701));
        await tester.pump();
        final intro = tester.widget<LessonIntroScreen>(
          find.byType(LessonIntroScreen),
        );
        expect(intro.lesson.number, choice.$2);
        expect(intro.relearnFromBeginning, choice.$3);
        expect(speech.commands.stops, 1);
        expect(store.pendingCompletionChoice, isNull);
        expect(media.startRecordingCount, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
  for (final systemBack in <bool>[false, true]) {
    testWidgets(
      'paused silent lesson exits via ${systemBack ? "system" : "screen"} Back with stalled audio',
      (tester) async {
        await _usePhoneSurface(tester);
        final registry = ActiveLearningModuleRegistry();
        addTearDown(registry.dispose);
        final voice = _BackStopVoice();
        final progress = _MemoryProgressStore()..currentSentence = 1;
        await tester.pumpWidget(
          ActiveLearningModuleScope(
            registry: registry,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => LessonPracticeScreen(
                        language: DisplayLanguage.vietnamese,
                        startAge: 3,
                        endAge: 5,
                        topic: listeningCatalogs.first.topics.first,
                        lesson: _lessonWithSentences(3),
                        progressStore: progress,
                        mediaService: _SilentMediaService(
                          existingRecordingPath: 'previous.m4a',
                        ),
                        voicePromptService: voice,
                        guideAudioLibrary: LessonGuideAudioLibrary(
                          assetPaths: const <String>[],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(await registry.pauseForMainAssistant(), isTrue);
        voice.blockStop = true;
        await tester.pump();
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byTooltip('Quay lại'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(LessonPracticeScreen), findsNothing);
        expect(progress.currentSentence, 1);
        voice.stopping.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('leaving during completion ting releases the already-open mic', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final store = _MemoryProgressStore()
      ..completedSentences = 1
      ..challengeProcessed = true
      ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd
      ..resumeStage = ListeningResumeStage.waitingForChoice;
    final speech = _CompletionCommandSpeechInput();
    addTearDown(speech.dispose);
    final cueGate = Completer<void>();
    final voice = _ReadyCueVoicePromptService(() {}, cueGate: cueGate);
    await tester.pumpWidget(
      _subject(
        _v4Lesson(),
        store,
        const Key('dispose-at-ting'),
        controller: _LearningAudioDependencies(speech),
        mediaService: _SilentMediaService(),
        voicePromptService: voice,
        initialResumeStage: ListeningResumeStage.waitingForChoice,
      ),
    );
    await tester.pumpAndSettle();
    expect(speech.commandStarts, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(speech.cancels, 1);
    cueGate.complete();
    await tester.pumpAndSettle();
    expect(speech.stops, 0);
  });

  for (final choice in [('Học lại', 1, true), ('Bài 2', 2, false)]) {
    testWidgets(
      'Android end-of-lesson "$choice" opens the selected learning flow',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await _usePhoneSurface(tester);
        final lesson = _v4Lesson();
        final next = _v4Lesson(number: 2);
        final store = _MemoryProgressStore()
          ..completedSentences = 1
          ..challengeProcessed = true
          ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd
          ..resumeStage = ListeningResumeStage.waitingForChoice;
        final speech = _CompletionCommandSpeechInput(choice.$1);
        addTearDown(speech.dispose);
        await tester.pumpWidget(
          _subject(
            lesson,
            store,
            Key('native-choice-${choice.$2}'),
            mediaService: _SilentMediaService(),
            voicePromptService: _SilentVoicePromptService(),
            controller: _LearningAudioDependencies(speech),
            topicContent: ListeningTopicContent(
              id: 'topic-1',
              number: 1,
              titleVi: 'Chủ đề 1',
              titleEn: 'Topic 1',
              lessons: [lesson, next],
            ),
            initialResumeStage: ListeningResumeStage.waitingForChoice,
          ),
        );
        await tester.pumpAndSettle();
        speech.partial.add(choice.$1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 701));
        await tester.pump();
        final intro = tester.widget<LessonIntroScreen>(
          find.byType(LessonIntroScreen),
        );
        expect(intro.lesson.number, choice.$2);
        expect(intro.relearnFromBeginning, choice.$3);
        expect(store.pendingCompletionChoice, isNull);
        expect(speech.stops, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }

  testWidgets('Android completion arms command ASR before ting, not Core mic', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final store = _MemoryProgressStore()
      ..completedSentences = 1
      ..challengeProcessed = true
      ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd
      ..resumeStage = ListeningResumeStage.waitingForChoice;
    final speech = _CompletionCommandSpeechInput();
    addTearDown(speech.dispose);
    final media = _SilentMediaService();
    final voice = _ReadyCueVoicePromptService(() {
      expect(speech.commandStarts, 1);
      expect(media.startRecordingCount, 0);
    });
    await tester.pumpWidget(
      _subject(
        _v4Lesson(),
        store,
        const Key('native-completion'),
        mediaService: media,
        voicePromptService: voice,
        controller: _LearningAudioDependencies(speech),
        initialResumeStage: ListeningResumeStage.waitingForChoice,
      ),
    );
    await tester.pumpAndSettle();
    expect(speech.commandStarts, 1);
    expect(voice.readyCues, 1);
    expect(media.startRecordingCount, 0);
    expect(
      store.pendingCompletionChoice,
      ListeningPendingChoiceStage.lessonEnd,
    );
    speech.partial.add('Dừng lại');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 701));
    await tester.pumpAndSettle();
    expect(speech.stops, 1);
    expect(store.pendingCompletionChoice, isNull);
    expect(store.resumeStage, ListeningResumeStage.completed);
    expect(find.byKey(const ValueKey<String>('v4-choice-stop')), findsNothing);
  });

  testWidgets(
    'next and previous both restart the selected sentence from its sample',
    (tester) async {
      await _usePhoneSurface(tester);
      final store = _MemoryProgressStore();
      final lesson = _lessonWithSentences(3);
      final mediaService = _SilentMediaService();

      await tester.pumpWidget(
        _subject(
          lesson,
          store,
          const Key('manual-navigation-audio'),
          mediaService: mediaService,
          guideAudioLibrary: LessonGuideAudioLibrary(
            assetPaths: const <String>[
              'assets/audio/A-3-5/GUIDE_PRAISE/praise.mp3',
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mediaService.playedUris, <Uri>[lesson.sentences.first.audioUri!]);

      await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
      await tester.pumpAndSettle();
      expect(find.text('Sentence 2'), findsOneWidget);
      expect(mediaService.playedUris, <Uri>[
        lesson.sentences.first.audioUri!,
        lesson.sentences[1].audioUri!,
      ]);

      await tester.tap(find.byKey(const Key('previous-lesson-sentence')));
      await tester.pumpAndSettle();
      expect(find.text('Sentence 1'), findsOneWidget);
      expect(mediaService.playedUris, <Uri>[
        lesson.sentences.first.audioUri!,
        lesson.sentences[1].audioUri!,
        Uri(
          scheme: 'asset',
          path: '/assets/audio/A-3-5/GUIDE_PRAISE/praise.mp3',
        ),
        lesson.sentences.first.audioUri!,
      ]);
    },
  );

  testWidgets('communication tab reports the lesson exit before navigation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _usePhoneSurface(tester);
    var communicationRequests = 0;

    await tester.pumpWidget(
      _subject(
        _lessonWithSentences(1),
        _MemoryProgressStore(),
        const Key('communication-exit'),
        onCommunicationRequested: () => communicationRequests += 1,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Giao tiếp'));
    await tester.pump();

    expect(communicationRequests, 1);
  });

  testWidgets('previous sentence is persisted and restored after re-entry', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final store = _MemoryProgressStore(currentSentence: 2);
    final lesson = _lessonWithSentences(3);

    await tester.pumpWidget(_subject(lesson, store, const Key('session-1')));
    await tester.pumpAndSettle();
    expect(find.text('Sentence 3'), findsOneWidget);
    var previousButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('previous-lesson-sentence')),
    );
    expect(
      previousButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
      Colors.white,
    );

    await tester.tap(find.byKey(const Key('previous-lesson-sentence')));
    await tester.pumpAndSettle();
    expect(find.text('Sentence 2'), findsOneWidget);
    expect(store.currentSentence, 1);

    await tester.pumpWidget(_subject(lesson, store, const Key('session-2')));
    await tester.pumpAndSettle();
    expect(find.text('Sentence 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('previous-lesson-sentence')));
    await tester.pumpAndSettle();
    expect(find.text('Sentence 1'), findsOneWidget);
    expect(store.currentSentence, 0);

    previousButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('previous-lesson-sentence')),
    );
    expect(previousButton.onPressed, isNull);
    expect(
      previousButton.style?.backgroundColor?.resolve(const <WidgetState>{
        WidgetState.disabled,
      }),
      Colors.white.withValues(alpha: 0.72),
    );
  });

  testWidgets('MAIN previous command replays the previous sentence flow', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final store = _MemoryProgressStore(currentSentence: 1);
    final lesson = _lessonWithSentences(3);
    final mediaService = _SilentMediaService();

    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: _subject(
          lesson,
          store,
          const Key('main-previous-command'),
          mediaService: mediaService,
          voicePromptService: _SilentVoicePromptService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sentence 2'), findsOneWidget);
    mediaService.playedUris.clear();

    await registry.execute(ActiveLearningCommand.stop);
    final operation = registry.execute(ActiveLearningCommand.previousItem);
    await tester.pump();
    final result = await operation;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result.wasHandled, isTrue);
    expect(find.text('Sentence 1'), findsOneWidget);
    expect(store.currentSentence, 0);
    expect(mediaService.playedUris, contains(lesson.sentences.first.audioUri));
  });

  testWidgets('review from beginning resets the resume sentence', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final store = _MemoryProgressStore();
    final lesson = _lessonWithSentences(1);

    await tester.pumpWidget(_subject(lesson, store, const Key('review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('lesson-review-screen')), findsOneWidget);
    final restartReview = find.byKey(const Key('restart-lesson-review'));
    await tester.ensureVisible(restartReview);
    await tester.tap(restartReview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(store.completedSentences, 1);
    expect(find.byKey(const Key('lesson-review-screen')), findsNothing);
    expect(find.text('Sentence 1'), findsOneWidget);
    expect(store.currentSentence, 0);
    expect(store.completedSentences, 1);
  });

  testWidgets('V4 resume ignores an archived attempt and restarts EN-VI-mic', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final store = _MemoryProgressStore();
    final mediaService = _SilentMediaService(
      existingRecordingPath: 'C:\\recordings\\previous-v4-attempt.m4a',
    );
    final voice = _RecordingVoicePromptService();
    final lesson = _v4Lesson();

    await tester.pumpWidget(
      _subject(
        lesson,
        store,
        const Key('v4-core-resume-with-archive'),
        mediaService: mediaService,
        voicePromptService: voice,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(voice.spoken, contains('Good morning.'));
    expect(voice.spoken, contains('Chào buổi sáng.'));
    expect(mediaService.recording, isTrue);
    expect(mediaService.startRecordingCount, 1);
  });

  testWidgets(
    'V4 marks the lesson complete only after its authored challenge finishes',
    (tester) async {
      await _usePhoneSurface(tester);
      final store = _MemoryProgressStore()..completedSentences = 1;
      final mediaService = _SilentMediaService(
        existingRecordingPath: 'C:\\recordings\\saved-v4-attempt.m4a',
      );
      final lesson = _v4Lesson();

      await tester.pumpWidget(
        _subject(
          lesson,
          store,
          const Key('v4-activity-completion'),
          mediaService: mediaService,
          voicePromptService: _SilentVoicePromptService(),
          completionChoiceRecognizer: _FixedCompletionChoiceRecognizer(
            'Dừng lại',
          ),
          initialResumeStage: ListeningResumeStage.challenge,
        ),
      );
      await tester.pumpAndSettle();

      expect(await store.hasCompletedV4LessonActivity(lesson.id), isFalse);
      final challenge = find.byKey(const Key('lesson-challenge-screen'));
      expect(challenge, findsOneWidget);
      expect(await store.hasCompletedV4LessonActivity(lesson.id), isFalse);
      final startsBeforeCompletion = mediaService.startRecordingCount;

      final challengeWidget = tester.widget<LessonChallengeScreen>(
        find.byType(LessonChallengeScreen),
      );
      await challengeWidget.onChallengeResolved!(
        challengeWidget.challenges.single,
        true,
      );

      Navigator.of(
        tester.element(find.byType(LessonChallengeScreen)),
      ).pop(true);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(await store.hasCompletedV4LessonActivity(lesson.id), isTrue);
      expect(store.completedSentences, lesson.sentences.length);
      expect(
        mediaService.startRecordingCount,
        greaterThan(startsBeforeCompletion),
      );
    },
  );

  testWidgets(
    'V4 skips the duplicate lesson-completion line right after a freshly '
    'finished challenge (no song stage)',
    (tester) async {
      await _usePhoneSurface(tester);
      final store = _MemoryProgressStore()..completedSentences = 1;
      final mediaService = _SilentMediaService(
        existingRecordingPath: 'C:\\recordings\\saved-v4-attempt.m4a',
      );
      final lesson = _v4Lesson();
      final voice = _KeyedRecordingVoicePromptService();

      await tester.pumpWidget(
        _subject(
          lesson,
          store,
          const Key('v4-challenge-completion-speech'),
          mediaService: mediaService,
          voicePromptService: voice,
          completionChoiceRecognizer: const _FixedCompletionChoiceRecognizer(
            'Dừng lại',
          ),
          initialResumeStage: ListeningResumeStage.challenge,
        ),
      );
      await tester.pumpAndSettle();

      final challengeWidget = tester.widget<LessonChallengeScreen>(
        find.byType(LessonChallengeScreen),
      );
      // The challenge screen itself already speaks "Bạn đã hoàn thành phần
      // thử thách rồi." right before popping `true` -- this mirrors that
      // contract without re-exercising LessonChallengeScreen's own TTS.
      await challengeWidget.onChallengeResolved!(
        challengeWidget.challenges.single,
        true,
      );
      Navigator.of(
        tester.element(find.byType(LessonChallengeScreen)),
      ).pop(true);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        voice.audioKeys,
        isNot(
          contains(
            ListeningAudioKeys.topicContextPrompt(
              'Bạn đã hoàn thành Bài ${lesson.number} rồi!',
            ),
          ),
        ),
      );
    },
  );

  testWidgets('Challenge intro is owned once by the pushed challenge route', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final voice = _KeyedRecordingVoicePromptService();
    await tester.pumpWidget(
      _subject(
        _v4Lesson(),
        _MemoryProgressStore()..completedSentences = 1,
        const Key('challenge-audio-handoff'),
        mediaService: _SilentMediaService(),
        voicePromptService: voice,
        initialResumeStage: ListeningResumeStage.challenge,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LessonChallengeScreen), findsOneWidget);
    expect(
      voice.audioKeys,
      containsAllInOrder(<String>[
        ListeningAudioKeys.challengeIntro,
        ListeningAudioKeys.challengePrompt('v4-challenge-1'),
        ListeningAudioKeys.challengeAnswerHandoff,
      ]),
    );
    expect(
      voice.audioKeys.where((key) => key == ListeningAudioKeys.challengeIntro),
      hasLength(1),
    );
  });

  testWidgets('MAIN during Challenge handoff waits for resume before audio', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final store = _GatedChallengeResumeStore()..completedSentences = 1;
    final media = _SilentMediaService();
    final voice = _KeyedRecordingVoicePromptService();
    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: _subject(
          _v4Lesson(),
          store,
          const Key('challenge-paused-handoff'),
          mediaService: media,
          voicePromptService: voice,
          initialResumeStage: ListeningResumeStage.challenge,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.challengeStagePending, isTrue);

    expect(await registry.pauseForMainAssistant(), isTrue);
    store.releaseChallengeStage();
    await tester.pumpAndSettle();
    expect(
      find.byType(LessonChallengeScreen, skipOffstage: false),
      findsNothing,
    );
    expect(voice.audioKeys, isEmpty);
    expect(media.startRecordingCount, 0);

    expect(
      (await registry.execute(ActiveLearningCommand.resume)).wasHandled,
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(LessonChallengeScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(voice.audioKeys, <String>[
      ListeningAudioKeys.challengeIntro,
      ListeningAudioKeys.challengePrompt('v4-challenge-1'),
      ListeningAudioKeys.challengeAnswerHandoff,
    ]);
    expect(media.startRecordingCount, 1);
    expect(media.startedSentenceIds, <String>['v4-challenge-1']);
  });

  for (final command in <ActiveLearningCommand>[
    ActiveLearningCommand.resume,
    ActiveLearningCommand.replayCurrent,
  ]) {
    testWidgets('stale Challenge entry after MAIN ${command.name} opens once', (
      tester,
    ) async {
      await _usePhoneSurface(tester);
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final store = _GatedChallengeResumeStore()..completedSentences = 1;
      final media = _SilentMediaService();
      final voice = _KeyedRecordingVoicePromptService();
      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: _subject(
            _v4Lesson(),
            store,
            const Key('challenge-pending-main-resume'),
            mediaService: media,
            voicePromptService: voice,
            initialResumeStage: ListeningResumeStage.challenge,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.challengeStagePending, isTrue);
      expect(find.byType(LessonChallengeScreen), findsNothing);

      expect(await registry.pauseForMainAssistant(), isTrue);
      expect((await registry.execute(command)).wasHandled, isTrue);
      await tester.pumpAndSettle();
      store.releaseChallengeStage();
      await tester.pumpAndSettle();

      expect(
        find.byType(LessonChallengeScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(voice.audioKeys, <String>[
        ListeningAudioKeys.challengeIntro,
        ListeningAudioKeys.challengePrompt('v4-challenge-1'),
        ListeningAudioKeys.challengeAnswerHandoff,
      ]);
      expect(media.startRecordingCount, 1);
      expect(media.startedSentenceIds, <String>['v4-challenge-1']);
    });
  }

  testWidgets('V4 resumes the exact completion choice after interruption', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final store = _MemoryProgressStore()
      ..completedSentences = 1
      ..challengeProcessed = true
      ..resumeStage = ListeningResumeStage.waitingForChoice
      ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd;
    store.completedV4LessonActivities.add('navigation-test-lesson');
    final mediaService = _SilentMediaService();
    final voicePromptService = _RecordingVoicePromptService();

    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: _subject(
          _v4Lesson(),
          store,
          const Key('v4-waiting-choice-resume'),
          mediaService: mediaService,
          voicePromptService: voicePromptService,
          completionChoiceRecognizer: const _FixedCompletionChoiceRecognizer(
            'Dừng lại',
          ),
          initialResumeStage: ListeningResumeStage.waitingForChoice,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lesson-challenge-screen')), findsNothing);
    expect(
      voicePromptService.spoken,
      containsAllInOrder(<String>[
        'Bạn đã hoàn thành Bài 1 rồi!',
        'Bạn muốn học bài tiếp theo hay học lại bài này?',
      ]),
    );
    expect(mediaService.startRecordingCount, 1);
    expect(
      store.pendingCompletionChoice,
      ListeningPendingChoiceStage.lessonEnd,
    );
    expect(store.resumeStage, ListeningResumeStage.waitingForChoice);

    expect(await registry.pauseForMainAssistant(), isTrue);
    expect(
      (await registry.execute(ActiveLearningCommand.resume)).wasHandled,
      isTrue,
    );
    await tester.pump();
    expect(mediaService.startRecordingCount, 2);
    expect(mediaService.startedSentenceIds.last, contains('completion-choice'));

    await tester.tap(find.byKey(const ValueKey<String>('v4-choice-stop')));
    await tester.pumpAndSettle();

    expect(store.pendingCompletionChoice, isNull);
    expect(store.resumeStage, ListeningResumeStage.completed);
  });

  testWidgets(
    'post-Challenge lesson choice uses the authored current-to-next key',
    (tester) async {
      await _usePhoneSurface(tester);
      final firstLesson = _v4Lesson();
      final nextLesson = _v4Lesson(number: 2);
      final store = _MemoryProgressStore()
        ..completedSentences = 1
        ..challengeProcessed = true
        ..resumeStage = ListeningResumeStage.waitingForChoice
        ..pendingCompletionChoice = ListeningPendingChoiceStage.lessonEnd;
      store.completedV4LessonActivities.add(firstLesson.id);
      final voice = _KeyedRecordingVoicePromptService();

      await tester.pumpWidget(
        _subject(
          firstLesson,
          store,
          const Key('post-challenge-authored-choice'),
          voicePromptService: voice,
          topicContent: ListeningTopicContent(
            id: 'navigation-test-topic',
            number: 1,
            titleVi: 'Chủ đề kiểm tra',
            titleEn: 'Test topic',
            lessons: <ListeningLessonContent>[firstLesson, nextLesson],
          ),
          initialResumeStage: ListeningResumeStage.waitingForChoice,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        voice.audioKeys,
        containsAllInOrder(<String>[
          ListeningAudioKeys.milestoneLesson(1),
          ListeningAudioKeys.completionLesson(1, 2),
        ]),
      );
      expect(voice.spoken, isEmpty);
    },
  );

  testWidgets('V4 resumes an interrupted song from its beginning', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final store = _MemoryProgressStore();
    final lesson = _v4Lesson(withSong: true);
    store.challengeProcessed = true;
    final mediaService = _SilentMediaService(
      existingRecordingPath: 'C:\\recordings\\saved-v4-attempt.m4a',
    );

    await tester.pumpWidget(
      _subject(
        lesson,
        store,
        const Key('v4-interrupted-song'),
        mediaService: mediaService,
        voicePromptService: _SilentVoicePromptService(),
        completionChoiceRecognizer: const _FixedCompletionChoiceRecognizer(
          'Dừng lại',
        ),
        initialResumeStage: ListeningResumeStage.song,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('v4-song-stage-screen')), findsNothing);
    expect(mediaService.playedUris, contains(lesson.songAudioUri));
    expect(await store.hasCompletedV4LessonActivity(lesson.id), isTrue);
    expect(store.resumeStage, ListeningResumeStage.waitingForChoice);
    expect(store.pendingCompletionChoice, ListeningPendingChoiceStage.topicEnd);

    await tester.tap(find.byKey(const ValueKey<String>('v4-choice-stop')));
    await tester.pumpAndSettle();

    expect(store.resumeStage, ListeningResumeStage.completed);
  });

  testWidgets('completion remains usable on a compact phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final store = _MemoryProgressStore();
    final lesson = _lessonWithSentences(1);

    await tester.pumpWidget(_subject(lesson, store, const Key('compact')));
    await tester.pumpAndSettle();
    final continueButton = find.byKey(const Key('continue-lesson-sentence'));
    await tester.ensureVisible(continueButton);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(continueButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('lesson-review-screen')), findsOneWidget);
    expect(find.text('Đã học'), findsOneWidget);
    final restartReview = find.byKey(const Key('restart-lesson-review'));
    final primaryAction = find.byKey(const Key('post-lesson-primary-action'));
    await tester.ensureVisible(primaryAction);
    await tester.pump(const Duration(milliseconds: 200));
    expect(restartReview, findsOneWidget);
    expect(primaryAction, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MAIN commands pause, resume, and leave the lesson for home', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final lesson = _lessonWithSentences(1);
    final mediaService = _SilentMediaService(
      existingRecordingPath: 'C:\\recordings\\previous-attempt.m4a',
    );

    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              key: const Key('test-home'),
              body: FilledButton(
                key: const Key('open-test-lesson'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => LessonPracticeScreen(
                      language: DisplayLanguage.vietnamese,
                      startAge: 3,
                      endAge: 5,
                      topic: listeningCatalogs.first.topics.first,
                      lesson: lesson,
                      progressStore: _MemoryProgressStore(),
                      mediaService: mediaService,
                      voicePromptService: _SilentVoicePromptService(),
                      guideAudioLibrary: LessonGuideAudioLibrary(
                        assetPaths: const <String>[],
                      ),
                    ),
                  ),
                ),
                child: const Text('Mở bài học'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-test-lesson')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isTrue);
    expect(registry.hasActiveModule, isTrue);
    expect(registry.isActiveModulePaused, isFalse);
    expect(mediaService.recording, isFalse);

    expect(
      (await registry.execute(ActiveLearningCommand.stop)).wasHandled,
      isTrue,
    );
    await tester.pump();
    expect(registry.isActiveModulePaused, isTrue);
    expect(mediaService.recording, isFalse);
    expect(find.text('Đã dừng. Nhấn MAIN để tiếp tục.'), findsOneWidget);

    expect(
      (await registry.execute(ActiveLearningCommand.resume)).wasHandled,
      isTrue,
    );
    await tester.pump();
    expect(registry.isActiveModulePaused, isFalse);
    expect(mediaService.recording, isTrue);
    expect(mediaService.startRecordingCount, 1);

    expect(
      (await registry.execute(ActiveLearningCommand.exitToHome)).wasHandled,
      isTrue,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(navigator.canPop(), isFalse);
    expect(find.byKey(const Key('test-home')), findsOneWidget);
    expect(find.byKey(const Key('lesson-practice-screen')), findsNothing);
    expect(registry.hasActiveModule, isFalse);
  });
}

Widget _subject(
  ListeningLessonContent lesson,
  ListeningProgressStore store,
  Key sessionKey, {
  LessonMediaService? mediaService,
  LessonGuideAudioLibrary? guideAudioLibrary,
  VoicePromptService? voicePromptService,
  LearningAudioDependencies? controller,
  ListeningTopicContent? topicContent,
  ListeningContentAgeGroup? contentGroup,
  ListeningLevelContent? levelContent,
  LessonCompletionChoiceRecognizer? completionChoiceRecognizer,
  ListeningResumeStage initialResumeStage = ListeningResumeStage.core,
  VoidCallback? onCommunicationRequested,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    builder: (context, child) {
      final mediaQuery = MediaQuery.of(context);
      return MediaQuery(
        data: mediaQuery.copyWith(disableAnimations: true),
        child: child!,
      );
    },
    home: LessonPracticeScreen(
      key: sessionKey,
      language: DisplayLanguage.vietnamese,
      startAge: 3,
      endAge: 5,
      topic: listeningCatalogs.first.topics.first,
      lesson: lesson,
      progressStore: store,
      mediaService: mediaService ?? _SilentMediaService(),
      voicePromptService: voicePromptService,
      controller: controller,
      topicContent: topicContent,
      contentGroup: contentGroup,
      levelContent: levelContent,
      completionChoiceRecognizer: completionChoiceRecognizer,
      initialResumeStage: initialResumeStage,
      onCommunicationRequested: onCommunicationRequested,
      guideAudioLibrary:
          guideAudioLibrary ??
          LessonGuideAudioLibrary(assetPaths: const <String>[]),
    ),
  );
}

ListeningLessonContent _lessonWithSentences(int count) {
  return ListeningLessonContent(
    id: 'navigation-test-lesson',
    number: 1,
    titleVi: 'Bài kiểm tra',
    titleEn: 'Test lesson',
    intro: 'Bắt đầu bài học.',
    outro: 'Con đã hoàn thành bài học rồi. Làm tốt lắm!',
    estimatedMinutes: 1,
    sentences: List<ListeningSentenceContent>.generate(
      count,
      (index) => ListeningSentenceContent(
        number: index + 1,
        english: 'Sentence ${index + 1}',
        audioUri: Uri.parse('https://example.com/sentence-${index + 1}.mp3'),
        vietnamese: 'Câu ${index + 1}',
      ),
      growable: false,
    ),
  );
}

ListeningLessonContent _v4Lesson({
  bool withSong = false,
  int number = 1,
  List<ListeningSentenceContent>? sentences,
}) {
  return ListeningLessonContent(
    id: number == 1
        ? 'navigation-test-lesson'
        : 'navigation-test-lesson-$number',
    code: 'C35-L1-T01-B0$number',
    number: number,
    titleVi: 'Bài V4',
    titleEn: 'V4 lesson',
    intro: '',
    outro: '',
    estimatedMinutes: 1,
    entry: ListeningLessonEntry(
      kind: ListeningLessonEntryKind.microObjective,
      text: 'Mình cùng học nhé.',
    ),
    challengeBank: <ListeningChallengeContent>[
      const ListeningChallengeContent(
        id: 'v4-challenge-1',
        format: 'VI_TO_EN',
        prompt: 'Chào buổi sáng.',
        choices: <String>['Good morning.', 'Good night.'],
        correctAnswer: 'Good morning.',
        correctVietnamese: 'Chào buổi sáng.',
        targetId: 'v4-target-1',
      ),
    ],
    sentences:
        sentences ??
        <ListeningSentenceContent>[
          const ListeningSentenceContent(
            id: 'v4-target-1',
            number: 1,
            english: 'Good morning.',
            vietnamese: 'Chào buổi sáng.',
          ),
        ],
    songTitle: withSong ? 'Count with Me' : null,
    songAudioId: withSong ? 'C35_L1_T01_B01_SONG' : null,
    songAudioUri: withSong
        ? Uri.parse('asset:/assets/audio/Count_with_Me.mp3')
        : null,
  );
}

class _GatedChallengeResumeStore extends _MemoryProgressStore {
  final Completer<void> _challengeStageGate = Completer<void>();
  bool challengeStagePending = false;

  void releaseChallengeStage() => _challengeStageGate.complete();

  @override
  Future<void> saveResumeStage(
    String lessonId,
    ListeningResumeStage stage,
  ) async {
    if (stage == ListeningResumeStage.challenge) {
      challengeStagePending = true;
      await _challengeStageGate.future;
    }
    await super.saveResumeStage(lessonId, stage);
  }
}

class _MemoryProgressStore extends ListeningProgressStore {
  _MemoryProgressStore({this.currentSentence = 0});

  int currentSentence;
  int completedSentences = 0;
  final Set<String> completedV4LessonActivities = <String>{};
  ListeningResumeStage resumeStage = ListeningResumeStage.core;
  final Set<String> earnedStars = <String>{};
  final Map<int, ListeningSessionResult> sessionResults =
      <int, ListeningSessionResult>{};
  bool coreStarted = false;
  bool challengeProcessed = false;
  int? currentChallengeIndex;
  int challengeRotationMask = 0;
  ListeningPendingChoiceStage? pendingCompletionChoice;

  @override
  Future<bool> hasLessonPendingRelearn(String lessonId) async => false;

  @override
  Future<void> resetLessonRun(String lessonId) async {
    currentSentence = 0;
    challengeProcessed = false;
    resumeStage = ListeningResumeStage.core;
  }

  @override
  Future<bool> hasStartedLessonCore(String lessonId) async => coreStarted;

  @override
  Future<void> markLessonCoreStarted(String lessonId) async {
    coreStarted = true;
  }

  @override
  Future<Map<String, int>> readAll() async => <String, int>{
    'navigation-test-lesson': completedSentences,
  };

  @override
  Future<int> readLesson(String lessonId) async => completedSentences;

  @override
  Future<int> readCurrentSentence(String lessonId) async => currentSentence;

  @override
  Future<Set<int>> readSkippedSentences(String lessonId) async => <int>{};

  @override
  Future<Set<int>> readNeedsPracticeSentences(String lessonId) async => <int>{};

  @override
  Future<Map<int, ListeningSessionResult>> readSessionResults(
    String lessonId,
  ) async => Map<int, ListeningSessionResult>.of(sessionResults);

  @override
  Future<ListeningSessionResult> readSessionResult(
    String lessonId,
    int sentenceIndex,
  ) async => sessionResults[sentenceIndex] ?? ListeningSessionResult.pending;

  @override
  Future<void> saveSessionResult(
    String lessonId,
    int sentenceIndex,
    ListeningSessionResult result,
  ) async {
    if (sessionResults[sentenceIndex] == ListeningSessionResult.achieved &&
        result != ListeningSessionResult.achieved) {
      return;
    }
    sessionResults[sentenceIndex] = result;
  }

  @override
  Future<bool> hasCompletedV4LessonActivity(String lessonId) async =>
      completedV4LessonActivities.contains(lessonId);

  @override
  Future<Set<String>> readCompletedV4LessonActivities() async =>
      Set<String>.of(completedV4LessonActivities);

  @override
  Future<bool> hasProcessedLessonChallenge(String lessonId) async =>
      challengeProcessed;

  @override
  Future<void> markLessonChallengeProcessed(String lessonId) async {
    challengeProcessed = true;
  }

  @override
  Future<int?> readCurrentChallengeIndex(String lessonId) async =>
      currentChallengeIndex;

  @override
  Future<void> saveCurrentChallengeIndex(String lessonId, int index) async {
    currentChallengeIndex = index;
  }

  @override
  Future<int> readChallengeRotationMask(String lessonId) async =>
      challengeRotationMask;

  @override
  Future<void> markChallengeUsed(
    String lessonId, {
    required int index,
    required int challengeCount,
  }) async {
    challengeRotationMask |= 1 << index;
    currentChallengeIndex = null;
  }

  @override
  Future<ListeningResumeStage> readResumeStage(String lessonId) async =>
      resumeStage;

  @override
  Future<void> saveResumeStage(
    String lessonId,
    ListeningResumeStage stage,
  ) async => resumeStage = stage;

  @override
  Future<void> savePendingCompletionChoice(
    String lessonId,
    ListeningPendingChoiceStage stage,
  ) async {
    pendingCompletionChoice = stage;
    resumeStage = ListeningResumeStage.waitingForChoice;
  }

  @override
  Future<ListeningPendingChoiceStage?> readPendingCompletionChoice(
    String lessonId,
  ) async => pendingCompletionChoice;

  @override
  Future<void> clearPendingCompletionChoice(String lessonId) async {
    pendingCompletionChoice = null;
    if (resumeStage == ListeningResumeStage.waitingForChoice) {
      resumeStage = ListeningResumeStage.completed;
    }
  }

  @override
  Future<bool> awardStar(String scopeId, String starId) async =>
      earnedStars.add(starId);

  @override
  Future<Set<String>> readEarnedStars(String scopeId) async =>
      Set<String>.of(earnedStars);

  @override
  Future<int> readTotalEarnedStars() async => earnedStars.length;

  @override
  Future<void> saveSkippedSentence(String lessonId, int sentenceIndex) async {}

  @override
  Future<void> clearSkippedSentence(String lessonId, int sentenceIndex) async {}

  @override
  Future<void> clearSkippedSentences(String lessonId) async {}

  @override
  Future<void> clearNeedsPracticeSentence(
    String lessonId,
    int sentenceIndex,
  ) async {}

  @override
  Future<void> clearNeedsPracticeSentences(String lessonId) async {}

  @override
  Future<void> saveLesson(String lessonId, int completed) async {
    if (completed > completedSentences) {
      completedSentences = completed;
    }
  }

  @override
  Future<void> saveCurrentSentence(String lessonId, int sentenceIndex) async {
    currentSentence = sentenceIndex;
  }

  @override
  Future<void> markV4LessonActivityCompleted(String lessonId) async {
    completedV4LessonActivities.add(lessonId);
  }
}

class _TopicTransitionProgressStore extends _MemoryProgressStore {
  final Map<String, int> progress = {};
  final Map<String, int> cursors = {};
  final Map<String, ListeningResumeStage> stages = {};

  @override
  Future<bool> hasOpenedLearningGuide() async => true;

  @override
  Future<void> markLearningGuideOpened() async {}

  @override
  Future<Map<String, int>> readAll() async => Map.of(progress);

  @override
  Future<int> readLesson(String lessonId) async => progress[lessonId] ?? 0;

  @override
  Future<int> readCurrentSentence(String lessonId) async =>
      cursors[lessonId] ?? 0;

  @override
  Future<void> saveCurrentSentence(String lessonId, int sentenceIndex) async {
    cursors[lessonId] = sentenceIndex;
  }

  @override
  Future<ListeningResumeStage> readResumeStage(String lessonId) async =>
      stages[lessonId] ?? ListeningResumeStage.core;

  @override
  Future<void> saveResumeStage(
    String lessonId,
    ListeningResumeStage stage,
  ) async {
    stages[lessonId] = stage;
  }
}

class _GatedNavigationProgressStore extends _MemoryProgressStore {
  _GatedNavigationProgressStore(this.command) : super(currentSentence: 1);

  final ActiveLearningCommand command;
  final Completer<void> _saveGate = Completer<void>();
  bool savePending = false;

  void releaseSave() => _saveGate.complete();

  @override
  Future<void> saveLesson(String lessonId, int completed) async {
    if (command == ActiveLearningCommand.nextItem && !_saveGate.isCompleted) {
      savePending = true;
      await _saveGate.future;
    }
    await super.saveLesson(lessonId, completed);
  }

  @override
  Future<void> saveCurrentSentence(String lessonId, int sentenceIndex) async {
    if (command == ActiveLearningCommand.previousItem &&
        !_saveGate.isCompleted) {
      savePending = true;
      // The write has already happened; its completion arrives after MAIN.
      await super.saveCurrentSentence(lessonId, sentenceIndex);
      await _saveGate.future;
      return;
    }
    await super.saveCurrentSentence(lessonId, sentenceIndex);
  }
}

class _GatedInitialCursorStore extends _MemoryProgressStore {
  _GatedInitialCursorStore() : super(currentSentence: 1);
  final Completer<void> _readGate = Completer<void>();
  void releaseRead() => _readGate.complete();
  @override
  Future<int> readCurrentSentence(String lessonId) async {
    await _readGate.future;
    return currentSentence;
  }
}

class _SilentMediaService extends LessonMediaService {
  _SilentMediaService({this.existingRecordingPath});

  String? existingRecordingPath;
  final List<Uri> playedUris = <Uri>[];
  bool recording = false;
  int startRecordingCount = 0;
  int selectedOutputPreparationCount = 0;
  int nativeHandoffCount = 0;
  final List<String> startedSentenceIds = <String>[];

  @override
  Future<void> preparePhoneSpeakerOutput() async {}

  @override
  Future<void> prepareSelectedLessonOutput() async {
    selectedOutputPreparationCount += 1;
  }

  @override
  void handoffSelectedLessonOutputToNativeCapture() {
    nativeHandoffCount += 1;
  }

  @override
  Future<String?> existingRecording({
    required String lessonId,
    required int sentenceNumber,
    String? sentenceId,
  }) async => existingRecordingPath;

  @override
  Future<void> deleteRecordingsForLesson(String lessonId) async {
    existingRecordingPath = null;
  }

  @override
  Future<void> startRecording({
    required String lessonId,
    required int sentenceNumber,
    String? lessonTitle,
    String? sentenceId,
    String? english,
    String? vietnamese,
    bool saveToHistory = true,
  }) async {
    recording = true;
    startRecordingCount += 1;
    startedSentenceIds.add(sentenceId ?? '');
  }

  @override
  Future<void> cancelRecording() async {
    recording = false;
  }

  @override
  Future<LessonRecording> stopRecording() async {
    recording = false;
    return const LessonRecording(
      filePath: 'C:\\recordings\\completion-choice.m4a',
      duration: Duration(seconds: 2),
    );
  }

  @override
  Future<void> play(
    Uri uri, {
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = 8.0,
    bool fixedPlaybackGain = false,
  }) async => playedUris.add(uri);

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = 8.0,
    bool fixedPlaybackGain = false,
  }) async => playedUris.add(uri);

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
}

class _SilentVoicePromptService implements VoicePromptService {
  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _BackStopVoice extends _SilentVoicePromptService {
  bool blockStop = false;
  final stopping = Completer<void>();
  @override
  Future<void> stop() => blockStop ? stopping.future : Future<void>.value();
}

class _RecordingVoicePromptService extends _SilentVoicePromptService {
  final List<String> spoken = <String>[];

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spoken.add(text);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);
}

class _KeyedRecordingVoicePromptService extends _RecordingVoicePromptService
    implements
        KeyedVoicePromptService,
        KeyedSelectedMediaOutputVoicePromptService {
  final List<String> audioKeys = <String>[];

  @override
  Future<void> speakAndWaitWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  }) async {
    audioKeys.add(audioKey);
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutputWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  }) => speakAndWaitWithAudioKey(audioKey, text, locale: locale);
}

class _FixedCompletionChoiceRecognizer
    implements LessonCompletionChoiceRecognizer {
  const _FixedCompletionChoiceRecognizer(this.transcript);

  final String transcript;

  @override
  Future<String> transcribe(LessonRecording recording) async => transcript;

  @override
  Future<void> dispose() async {}
}

class _LearningAudioDependencies implements LearningAudioDependencies {
  _LearningAudioDependencies(this.learningSpeechInput);
  @override
  final StreamingSpeechInput learningSpeechInput;
  @override
  AudioTurnCoordinator? get audioTurnCoordinator => null;
  @override
  HfpAudioControl? createLearningAudioRouteControl() => null;
}

class _CompletionCommandSpeechInput
    implements StreamingSpeechInput, CommandStreamingSpeechInput {
  _CompletionCommandSpeechInput([this.transcript = 'Dừng lại']);
  final String transcript;
  final partial = StreamController<String>.broadcast();
  final done = StreamController<void>.broadcast();
  int commandStarts = 0;
  int stops = 0;
  int cancels = 0;
  @override
  String get label => 'test command ASR';
  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();
  @override
  Stream<void> get completed => done.stream;
  @override
  Stream<String> get partialText => partial.stream;
  @override
  Future<bool> checkAvailability() async => true;
  @override
  Future<void> start() async => fail('Completion must use command recognition');
  @override
  Future<void> startCommandRecognition() async {
    commandStarts++;
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    stops++;
    return StreamingSpeechCapture(
      sourceText: transcript,
      duration: Duration(seconds: 1),
      inputLabel: 'test',
      confidence: 0.95,
      firstResultMs: 100,
      finalAfterStopMs: 0,
    );
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> dispose() async {
    await partial.close();
    await done.close();
  }
}

class _IosCompletionCommandSpeechInput extends IOSStreamingSpeechInput {
  _IosCompletionCommandSpeechInput(String transcript)
    : commands = _CompletionCommandSpeechInput(transcript),
      super(eventStream: const Stream<dynamic>.empty());
  final _CompletionCommandSpeechInput commands;
  bool failStart = false;
  Completer<void>? firstStopGate;
  Completer<void>? firstStartGate;
  bool firstStartFails = false;
  @override
  Stream<double> get amplitudeDbfs => commands.amplitudeDbfs;
  @override
  Stream<void> get completed => commands.completed;
  @override
  Stream<String> get partialText => commands.partialText;
  @override
  Future<void> startCommandRecognition() async {
    await commands.startCommandRecognition();
    if (commands.commandStarts == 1) {
      await firstStartGate?.future;
      if (firstStartFails) {
        throw const StreamingSpeechInputException(
          'Old start failed',
          code: 'CANCELLED',
        );
      }
    }
    if (failStart) {
      throw const StreamingSpeechInputException(
        'Speech permission denied',
        code: 'SPEECH_PERMISSION_DENIED',
      );
    }
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    final capture = await commands.stop();
    if (commands.stops == 1) await firstStopGate?.future;
    return capture;
  }

  @override
  Future<void> cancel() => commands.cancel();
  @override
  Future<void> dispose() => commands.dispose();
}

class _ReadyCueVoicePromptService extends _SilentVoicePromptService
    implements SpeechReadyCuePlayer {
  _ReadyCueVoicePromptService(this.onCue, {this.cueGate});
  final Completer<void>? cueGate;
  final VoidCallback onCue;
  int readyCues = 0;
  @override
  Future<void> playSpeechReadyCue() async {
    readyCues++;
    onCue();
    await cueGate?.future;
  }
}

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
