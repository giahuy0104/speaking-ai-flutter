import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/adaptive_voice_activity_detector.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/learning_audio_dependencies.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_recording_endpoint_detector.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_session_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_flow_v3.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_practice_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final pendingStart in <bool>[true, false]) {
    testWidgets(
      'iOS Review cancels pending ${pendingStart ? "start" : "stop"} without touching a newer turn',
      (tester) async {
        final registry = ActiveLearningModuleRegistry();
        final media = _FakeLessonMediaService();
        final voice = _FakeVoicePromptService();
        final speech = _GatedIosLessonInput(
          startGate: pendingStart ? Completer<void>() : null,
        );
        addTearDown(registry.dispose);
        addTearDown(media.close);
        addTearDown(speech.dispose);
        await _mountReview(
          tester,
          registry: registry,
          media: media,
          voice: voice,
          evaluator: null,
          audioDependencies: _IosLearningDependencies(speech),
        );
        await tester.tap(
          find.byKey(const Key('vocabulary-practice-main-action')),
        );
        await tester.pumpAndSettle();
        expect(speech.startCalls, 1);
        expect(media.startCalls, 0);
        if (!pendingStart) {
          await tester.tap(
            find.byKey(const Key('vocabulary-practice-main-action')),
          );
          await tester.pumpAndSettle();
          expect(speech.stopCalls, 1);
        }
        await registry.pauseForMainAssistant();
        expect(speech.cancelCalls, 1);
        if (pendingStart) {
          speech.startGate!.complete();
        } else {
          await registry.execute(ActiveLearningCommand.nextItem);
          await tester.pumpAndSettle();
          expect(speech.startCalls, 2);
          speech.stopGate.completeError(
            const StreamingSpeechInputException(
              'Old turn cancelled',
              code: 'SPEECH_START_CANCELLED',
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(speech.cancelCalls, 1);
        expect(speech.takeRecordingCalls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  for (final systemBack in <bool>[false, true]) {
    testWidgets(
      'unfinished Today exits with ${systemBack ? "system" : "screen"} Back even if audio stop hangs',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        const store = VocabularyStore();
        const sessions = VocabularySessionStore();
        await store.addParentEntries(const <VocabularyTranslation>[
          VocabularyTranslation(
            englishText: 'Apple',
            vietnameseText: 'Quả táo',
          ),
        ]);
        final session = (await sessions.prepareToday(store))!;
        final voice = _BlockedBackVoice();
        final media = _FakeLessonMediaService();
        addTearDown(media.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => VocabularyPracticeScreen(
                      language: DisplayLanguage.vietnamese,
                      childAge: 6,
                      session: session,
                      store: store,
                      sessionStore: sessions,
                      mediaService: media,
                      attemptEvaluator: const RecordedAttemptEvaluator(),
                      voicePromptService: voice,
                      autoStart: false,
                      samplePause: Duration.zero,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('vocabulary-practice-main-action')),
        );
        await tester.pump();
        expect(voice.spoken, isNotEmpty);
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        }
        await tester.pumpAndSettle();
        expect(find.byType(VocabularyPracticeScreen), findsNothing);
        expect(voice.stopCalls, greaterThan(0));
        expect((await sessions.readActive())?.currentIndex, 0);
        final spokenCount = voice.spoken.length;
        voice.speech.complete();
        voice.stopping.complete();
        await tester.pumpAndSettle();
        expect(voice.spoken, hasLength(spokenCount));
        expect((await sessions.readActive())?.currentIndex, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Today stops after five listen-only items and MAIN timeout never replays',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = VocabularyStore();
      const sessionStore = VocabularySessionStore();
      await store.addParentEntries(const <VocabularyTranslation>[
        VocabularyTranslation(englishText: 'Apple', vietnameseText: 'Quả táo'),
        VocabularyTranslation(
          englishText: 'Banana',
          vietnameseText: 'Quả chuối',
        ),
        VocabularyTranslation(englishText: 'Cat', vietnameseText: 'Con mèo'),
      ], now: DateTime(2026, 9, 10, 8));
      await store.addParentEntries(const <VocabularyTranslation>[
        VocabularyTranslation(englishText: 'Dog', vietnameseText: 'Con chó'),
        VocabularyTranslation(englishText: 'Egg', vietnameseText: 'Quả trứng'),
      ], now: DateTime(2026, 9, 10, 8));
      final session = await sessionStore.prepareToday(
        store,
        now: DateTime(2026, 9, 10, 9),
      );
      final media = _FakeLessonMediaService();
      addTearDown(media.close);
      final voice = _FakeVoicePromptService();
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      String? capturedNoSpeechRetryPrompt;
      String? capturedNoSpeechExitPrompt;

      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: VocabularyPracticeScreen(
              language: DisplayLanguage.vietnamese,
              childAge: 6,
              session: session!,
              store: store,
              sessionStore: sessionStore,
              mediaService: media,
              attemptEvaluator: const RecordedAttemptEvaluator(),
              voicePromptService: voice,
              samplePause: Duration.zero,
              autoStart: false,
              onRequestVoiceChoice:
                  ({
                    String? noSpeechRetryPrompt,
                    String? noSpeechExitPrompt,
                  }) async {
                    capturedNoSpeechRetryPrompt = noSpeechRetryPrompt;
                    capturedNoSpeechExitPrompt = noSpeechExitPrompt;
                  },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('vocabulary-practice-main-action')),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 5; index++) {
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
      }
      expect(media.recording, isFalse);
      expect(voice.spoken.take(2), <String>['en-US:Apple', 'vi-VN:Quả táo']);
      expect(
        voice.spoken.any(
          (item) => item.contains(LessonGuideFlowV2.coreSpeakCue(0).text),
        ),
        isFalse,
      );

      expect(find.text(VocabularyFlowV3.todayCompletion), findsOneWidget);
      final learned = await store.read();
      expect(learned, hasLength(5));
      for (final entry in learned) {
        expect(entry.status, VocabularyLearningStatus.learnedWell);
        expect(entry.todayStatus, TodayVocabularyStatus.heard);
        expect(entry.isUnlockedParent, isTrue);
        expect(entry.correctAudioPath, isNull);
      }
      expect(await sessionStore.readActive(), isNull);
      expect(capturedNoSpeechRetryPrompt, VocabularyFlowV3.todayCompletion);
      expect(capturedNoSpeechExitPrompt, VocabularyFlowV3.pauseAfterNoResponse);
      expect(
        voice.spoken.where((text) => text.startsWith('en-US:')),
        hasLength(5),
      );
      expect(await registry.pauseForMainAssistant(), isTrue);
      expect(
        (await registry.execute(ActiveLearningCommand.resume)).wasHandled,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(find.text(VocabularyFlowV3.todayCompletion), findsOneWidget);
      expect(
        voice.spoken.where((text) => text.startsWith('en-US:')),
        hasLength(5),
      );
      expect(await sessionStore.readActive(), isNull);
    },
  );

  testWidgets(
    'Review shows one combined listen-and-repeat action without a card speaker',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = VocabularyStore();
      const sessionStore = VocabularySessionStore();
      await store.upsertLessonSentence(
        lessonCode: 'L01',
        sentenceId: 'S1',
        english: 'At noon',
        vietnamese: 'Buổi trưa',
        collection: VocabularyCollection.review,
        source: VocabularySource.topicCore,
      );
      final session = await sessionStore.prepareReview(store);
      final media = _FakeLessonMediaService();
      addTearDown(media.close);
      final voice = _FakeVoicePromptService();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: VocabularyPracticeScreen(
            language: DisplayLanguage.vietnamese,
            childAge: 6,
            session: session!,
            store: store,
            sessionStore: sessionStore,
            mediaService: media,
            attemptEvaluator: const RecordedAttemptEvaluator(),
            voicePromptService: voice,
            samplePause: Duration.zero,
            autoStart: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nghe và nói lại'), findsOneWidget);
      expect(find.text('Nghe mẫu'), findsNothing);
      expect(find.text('Giữ để nói'), findsNothing);
      expect(find.text('Về Main'), findsNothing);
      expect(
        find.byKey(const Key('vocabulary-practice-homi-stage')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('assets/images/mascot/penguin-listen.png'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('vocabulary-practice-entry')),
          matching: find.byIcon(Icons.volume_up_rounded),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const Key('vocabulary-practice-main-action')),
      );
      await tester.pumpAndSettle();

      expect(media.recording, isTrue);
      expect(media.startCalls, 1);
      expect(media.stopCalls, 0);
      expect(
        find.byKey(
          const ValueKey<String>('assets/images/mascot/penguin-speak.png'),
        ),
        findsOneWidget,
      );
      expect(voice.spoken.take(2), <String>[
        'en-US:At noon',
        'vi-VN:Buổi trưa',
      ]);
    },
  );

  testWidgets(
    'Review retries with English only and stops early after speech silence',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = VocabularyStore();
      const sessionStore = VocabularySessionStore();
      await store.upsertLessonSentence(
        lessonCode: 'L01',
        sentenceId: 'S1',
        english: 'Open your book',
        vietnamese: 'Mở sách ra',
        collection: VocabularyCollection.review,
        source: VocabularySource.topicCore,
      );
      final session = await sessionStore.prepareReview(store);
      final media = _FakeLessonMediaService();
      addTearDown(media.close);
      final voice = _FakeVoicePromptService();
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final evaluator = _QueuedAttemptEvaluator(<LessonAttemptOutcome>[
        LessonAttemptOutcome.retry,
        LessonAttemptOutcome.good,
      ]);
      var now = DateTime(2026);
      final endpointDetector = LessonRecordingEndpointDetector(
        silenceDuration: const Duration(milliseconds: 100),
        voiceActivityDetector: AdaptiveVoiceActivityDetector(
          calibrationDuration: Duration.zero,
          minimumSpeechDuration: Duration.zero,
          minimumSpeechVariationDb: 0,
        ),
        now: () => now,
      );

      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: VocabularyPracticeScreen(
              language: DisplayLanguage.vietnamese,
              childAge: 6,
              session: session!,
              store: store,
              sessionStore: sessionStore,
              mediaService: media,
              attemptEvaluator: evaluator,
              recordingEndpointDetector: endpointDetector,
              voicePromptService: voice,
              samplePause: Duration.zero,
              autoStart: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('vocabulary-practice-main-action')),
      );
      await tester.pumpAndSettle();
      expect(media.recording, isTrue);

      await tester.tap(
        find.byKey(const Key('vocabulary-practice-main-action')),
      );
      await tester.pumpAndSettle();
      expect(evaluator.attemptNumbers, <int>[1]);
      expect(media.recording, isTrue);
      expect(
        voice.spoken.where((item) => item == 'en-US:Open your book'),
        hasLength(2),
      );
      expect(
        voice.spoken.where((item) => item == 'vi-VN:Mở sách ra'),
        hasLength(1),
      );
      expect(
        voice.spoken.where(
          (item) => item == 'vi-VN:${LessonGuideFlowV2.coreSpeakCue(0).text}',
        ),
        hasLength(1),
      );

      media.amplitudes
        ..add(-60)
        ..add(-60)
        ..add(-60);
      now = now.add(const Duration(milliseconds: 100));
      media.amplitudes.add(-20);
      now = now.add(const Duration(milliseconds: 100));
      media.amplitudes.add(-60);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(evaluator.attemptNumbers, <int>[1, 2]);
      expect(media.stopCalls, 2);
      expect(media.recording, isFalse);
      expect(find.text(VocabularyFlowV3.reviewCycleFinished), findsOneWidget);
      expect(
        find.byKey(const Key('vocabulary-continue-learning')),
        findsNothing,
      );
      expect(await sessionStore.readActive(), isNull);

      expect(await registry.pauseForMainAssistant(), isTrue);
      final resume = await registry.execute(ActiveLearningCommand.resume);
      await tester.pump();
      expect(resume.status, ActiveLearningCommandStatus.unavailable);
      expect(resume.spokenReply, VocabularyFlowV3.reviewCycleFinished);
      expect(find.text(VocabularyFlowV3.reviewCycleFinished), findsOneWidget);
    },
  );

  testWidgets(
    'completed block lets MAIN route directly to Stars after interruption',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = VocabularyStore();
      const sessionStore = VocabularySessionStore();
      await store.addParentEntries(const <VocabularyTranslation>[
        VocabularyTranslation(englishText: 'Apple', vietnameseText: 'Quả táo'),
      ], now: DateTime(2026, 9, 10, 8));
      final session = await sessionStore.prepareToday(
        store,
        now: DateTime(2026, 9, 10, 9),
      );
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final media = _FakeLessonMediaService();
      addTearDown(media.close);
      VocabularyPracticeResult? result;

      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => FilledButton(
                key: const Key('open-vocabulary-practice'),
                onPressed: () async {
                  result = await Navigator.of(context).push(
                    MaterialPageRoute<VocabularyPracticeResult>(
                      builder: (_) => VocabularyPracticeScreen(
                        language: DisplayLanguage.vietnamese,
                        childAge: 6,
                        session: session!,
                        store: store,
                        sessionStore: sessionStore,
                        mediaService: media,
                        attemptEvaluator: const RecordedAttemptEvaluator(),
                        voicePromptService: _FakeVoicePromptService(),
                        samplePause: Duration.zero,
                        autoStart: false,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-vocabulary-practice')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('vocabulary-practice-main-action')),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text(VocabularyFlowV3.todayCompletion), findsOneWidget);

      expect(await registry.pauseForMainAssistant(), isTrue);
      final command = await registry.execute(
        ActiveLearningCommand.vocabularyStars,
      );
      await tester.pumpAndSettle();

      expect(command.wasHandled, isTrue);
      expect(result, VocabularyPracticeResult.stars);
      expect(find.text(VocabularyFlowV3.finishActiveGroupFirst), findsNothing);
    },
  );

  testWidgets('Review pauses only after two invalid microphone turns', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const store = VocabularyStore();
    const sessionStore = VocabularySessionStore();
    await store.upsertLessonSentence(
      lessonCode: 'L01',
      sentenceId: 'S1',
      english: 'Open your book',
      vietnamese: 'Mở sách ra',
      collection: VocabularyCollection.review,
      source: VocabularySource.topicCore,
    );
    final session = await sessionStore.prepareReview(store);
    final media = _FakeLessonMediaService();
    addTearDown(media.close);
    final voice = _FakeVoicePromptService();
    final evaluator = _QueuedAttemptEvaluator(<LessonAttemptOutcome>[
      LessonAttemptOutcome.noResponse,
      LessonAttemptOutcome.unclear,
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: VocabularyPracticeScreen(
          language: DisplayLanguage.vietnamese,
          childAge: 6,
          session: session!,
          store: store,
          sessionStore: sessionStore,
          mediaService: media,
          attemptEvaluator: evaluator,
          voicePromptService: voice,
          samplePause: Duration.zero,
          autoStart: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vocabulary-practice-main-action')));
    await tester.pumpAndSettle();
    expect(media.startCalls, 1);

    await tester.tap(find.byKey(const Key('vocabulary-practice-main-action')));
    await tester.pumpAndSettle();
    expect(media.startCalls, 2);
    expect(media.recording, isTrue);
    expect(
      find.byKey(const Key('vocabulary-resume-after-no-response')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('vocabulary-practice-main-action')));
    await tester.pumpAndSettle();
    expect(media.startCalls, 2);
    expect(media.recording, isFalse);
    expect(find.text(VocabularyFlowV3.pauseAfterNoResponse), findsOneWidget);
    expect(
      find.byKey(const Key('vocabulary-resume-after-no-response')),
      findsOneWidget,
    );
  });

  testWidgets('system Back preserves an unfinished Today checkpoint', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const store = VocabularyStore();
    const sessionStore = VocabularySessionStore();
    await store.addParentEntries(const <VocabularyTranslation>[
      VocabularyTranslation(englishText: 'Apple', vietnameseText: 'Quả táo'),
    ], now: DateTime(2026, 9, 10, 8));
    final session = await sessionStore.prepareToday(
      store,
      now: DateTime(2026, 9, 10, 9),
    );
    final media = _FakeLessonMediaService();
    final voice = _FakeVoicePromptService();
    addTearDown(media.close);
    VocabularyPracticeResult? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => FilledButton(
            key: const Key('open-vocabulary-practice'),
            onPressed: () async {
              result = await Navigator.of(context).push(
                MaterialPageRoute<VocabularyPracticeResult>(
                  builder: (_) => VocabularyPracticeScreen(
                    language: DisplayLanguage.vietnamese,
                    childAge: 6,
                    session: session!,
                    store: store,
                    sessionStore: sessionStore,
                    mediaService: media,
                    voicePromptService: voice,
                    samplePause: Duration.zero,
                    autoStart: false,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-vocabulary-practice')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(VocabularyPracticeScreen), findsNothing);
    expect(find.text(VocabularyFlowV3.finishActiveGroupFirst), findsNothing);
    expect((await sessionStore.readActive())?.currentIndex, 0);
    expect(voice.spoken, isEmpty);
    expect(result, isNull);
  });

  testWidgets(
    'Review MAIN controls always play EN then VI before cue and mic',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final media = _FakeLessonMediaService();
      final voice = _GatedCueVoice(media);
      addTearDown(registry.dispose);
      addTearDown(media.close);
      await _mountReview(
        tester,
        registry: registry,
        media: media,
        voice: voice,
      );
      final context = registry.controller! as ActiveLearningVoiceContext;
      expect(context.mainVoiceNode, ActiveLearningVoiceNode.review);
      expect(
        context.mainVoicePrompt,
        MasterNavigationContract.coreControlPrompt,
      );
      for (final scenario in <(ActiveLearningCommand, String, String, String?)>[
        (
          ActiveLearningCommand.previousItem,
          'Apple',
          'Quả táo',
          'Đây là câu đầu tiên. Mình nghe lại nhé.',
        ),
        (
          ActiveLearningCommand.nextItem,
          'Banana',
          'Quả chuối',
          MasterNavigationContract.nextItemPrompt,
        ),
        (
          ActiveLearningCommand.nextItem,
          'Banana',
          'Quả chuối',
          'Đây là câu cuối. Bạn hãy hoàn thành câu này nhé.',
        ),
        (ActiveLearningCommand.previousItem, 'Apple', 'Quả táo', null),
        (ActiveLearningCommand.replayCurrent, 'Apple', 'Quả táo', null),
      ]) {
        await registry.pauseForMainAssistant();
        final before = media.startCalls;
        voice.spoken.clear();
        voice.gates = <String, Completer<void>>{
          'en-US:${scenario.$2}': Completer<void>(),
          'vi-VN:${scenario.$3}': Completer<void>(),
        };
        voice.cue = Completer<void>();
        final command = registry.execute(scenario.$1);
        await tester.pumpAndSettle();
        expect(voice.spoken, <String>[
          if (scenario.$4 != null) 'vi-VN:${scenario.$4}',
          'en-US:${scenario.$2}',
        ]);
        expect(media.startCalls, before);
        voice.gates['en-US:${scenario.$2}']!.complete();
        await tester.pumpAndSettle();
        expect(voice.spoken.last, 'vi-VN:${scenario.$3}');
        expect(media.startCalls, before);
        voice.gates['vi-VN:${scenario.$3}']!.complete();
        await tester.pumpAndSettle();
        expect(media.events.last, 'cue');
        expect(media.events[media.events.length - 2], 'prepare');
        expect(media.startCalls, before);
        voice.cue!.complete();
        await tester.pumpAndSettle();
        expect((await command).wasHandled, isTrue);
        expect(media.startCalls, before + 1);
        expect(media.events.last, 'record');
      }
      await registry.pauseForMainAssistant();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final cancel in <bool>[false, true]) {
    testWidgets(
      'Android Review does not record after cue ${cancel ? "cancellation" : "failure"}',
      (tester) async {
        final registry = ActiveLearningModuleRegistry();
        final media = _FakeLessonMediaService();
        final voice = _GatedCueVoice(media)..cue = Completer<void>();
        addTearDown(registry.dispose);
        addTearDown(media.close);
        await _mountReview(
          tester,
          registry: registry,
          media: media,
          voice: voice,
        );
        await tester.tap(
          find.byKey(const Key('vocabulary-practice-main-action')),
        );
        await tester.pumpAndSettle();
        expect(media.events.last, 'cue');
        expect(media.startCalls, 0);
        if (cancel) {
          await registry.pauseForMainAssistant();
          voice.cue!.complete();
        } else {
          voice.cue!.completeError(StateError('H20 cue failed'));
        }
        await tester.pumpAndSettle();
        expect(media.startCalls, 0);
        expect(media.recording, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'Review next keeps skipped items pending after completing the block',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final media = _FakeLessonMediaService();
      final voice = _FakeVoicePromptService();
      addTearDown(registry.dispose);
      addTearDown(media.close);
      await _mountReview(
        tester,
        registry: registry,
        media: media,
        voice: voice,
        evaluator: _QueuedAttemptEvaluator([LessonAttemptOutcome.good]),
      );
      await registry.pauseForMainAssistant();
      expect(
        (await registry.execute(ActiveLearningCommand.nextItem)).wasHandled,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(media.recording, isTrue);
      expect(voice.spoken.take(3), [
        'vi-VN:${MasterNavigationContract.nextItemPrompt}',
        'en-US:Banana',
        'vi-VN:Quả chuối',
      ]);
      await tester.tap(
        find.byKey(const Key('vocabulary-practice-main-action')),
      );
      await tester.pumpAndSettle();
      const store = VocabularyStore();
      const sessions = VocabularySessionStore();
      final entries = await store.reviewEntries();
      expect(entries.map((entry) => entry.word), contains('Apple'));
      expect(await sessions.hasPendingReviewEntries(store), isTrue);
      final snapshot = (await sessions.readReviewSessionSnapshot())!;
      expect(snapshot.triedEntryIds, hasLength(1));
      expect(
        snapshot.triedEntryIds,
        isNot(
          contains(entries.singleWhere((entry) => entry.word == 'Apple').id),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}

Future<void> _mountReview(
  WidgetTester tester, {
  required ActiveLearningModuleRegistry registry,
  required _FakeLessonMediaService media,
  required VoicePromptService voice,
  LessonAttemptEvaluator? evaluator = const RecordedAttemptEvaluator(),
  LearningAudioDependencies? audioDependencies,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  const store = VocabularyStore();
  const sessions = VocabularySessionStore();
  for (final item in <(String, String)>[
    ('Apple', 'Quả táo'),
    ('Banana', 'Quả chuối'),
  ]) {
    await store.upsertLessonSentence(
      lessonCode: 'L01',
      sentenceId: item.$1,
      english: item.$1,
      vietnamese: item.$2,
      collection: VocabularyCollection.review,
      source: VocabularySource.topicCore,
    );
  }
  final prepared = (await sessions.prepareReview(store))!;
  final entries = (await store.read()).toList()
    ..sort((left, right) => left.word.compareTo(right.word));
  final session = prepared.copyWith(
    entryIds: entries.map((entry) => entry.id).toList(),
  );
  await tester.pumpWidget(
    ActiveLearningModuleScope(
      registry: registry,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: VocabularyPracticeScreen(
          language: DisplayLanguage.vietnamese,
          childAge: 6,
          session: session,
          store: store,
          sessionStore: sessions,
          mediaService: media,
          voicePromptService: voice,
          attemptEvaluator: evaluator,
          audioDependencies: audioDependencies,
          autoStart: false,
          samplePause: Duration.zero,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeLessonMediaService extends LessonMediaService {
  final events = <String>[];
  bool recording = false;
  int startCalls = 0;
  int stopCalls = 0;
  final StreamController<double> amplitudes =
      StreamController<double>.broadcast(sync: true);

  @override
  Stream<double> get recordingAmplitudeDbfs => amplitudes.stream;

  @override
  Future<String> recordingPath({
    required String lessonId,
    required int sentenceNumber,
    String? extension,
  }) async => '/recordings/$lessonId-$sentenceNumber.${extension ?? 'm4a'}';

  @override
  Future<void> prepareSelectedLessonOutput() async {
    events.add('prepare');
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
    events.add('record');
    recording = true;
    startCalls += 1;
  }

  @override
  Future<LessonRecording> stopRecording() async {
    recording = false;
    stopCalls += 1;
    return const LessonRecording(
      filePath: '/recordings/apple.m4a',
      duration: Duration(seconds: 2),
    );
  }

  @override
  Future<void> cancelRecording() async {
    recording = false;
  }

  @override
  Future<void> stopPlayback() async {}

  Future<void> close() => amplitudes.close();
}

class _GatedIosLessonInput extends IOSStreamingSpeechInput {
  _GatedIosLessonInput({this.startGate})
    : super(eventStream: const Stream<dynamic>.empty());

  final Completer<void>? startGate;
  final stopGate = Completer<StreamingSpeechCapture>();
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  int takeRecordingCalls = 0;

  @override
  Future<void> startLessonEnglishRecognitionWithRecording(String path) async {
    startCalls++;
    await startGate?.future;
  }

  @override
  Future<StreamingSpeechCapture> stop() {
    stopCalls++;
    return stopGate.future;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  AudioCapture? takeLessonRecordingAudioCapture() {
    takeRecordingCalls++;
    return null;
  }
}

class _IosLearningDependencies implements LearningAudioDependencies {
  const _IosLearningDependencies(this.learningSpeechInput);

  @override
  final StreamingSpeechInput learningSpeechInput;

  @override
  AudioTurnCoordinator? get audioTurnCoordinator => null;

  @override
  HfpAudioControl? createLearningAudioRouteControl() => null;
}

class _BlockedBackVoice extends _FakeVoicePromptService {
  final speech = Completer<void>();
  final stopping = Completer<void>();
  int stopCalls = 0;

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) {
    spoken.add(text);
    return speech.future;
  }

  @override
  Future<void> stop() {
    stopCalls++;
    return stopping.future;
  }
}

class _QueuedAttemptEvaluator implements LessonAttemptEvaluator {
  _QueuedAttemptEvaluator(this.outcomes);

  final List<LessonAttemptOutcome> outcomes;
  final List<int> attemptNumbers = <int>[];

  @override
  Future<LessonAttemptOutcome> evaluate({
    required String lessonCode,
    required String sentenceId,
    required String expectedEnglish,
    required String recordingPath,
    required Duration recordingDuration,
    required int attemptNumber,
    required int childAge,
    Iterable<String> acceptedVariants = const <String>[],
    bool requireAllExpectedTokens = false,
  }) async {
    attemptNumbers.add(attemptNumber);
    return outcomes.removeAt(0);
  }
}

class _FakeVoicePromptService implements VoicePromptService {
  final List<String> spoken = <String>[];

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spoken.add('$locale:$text');
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);

  @override
  Future<void> stop() async {}
}

class _GatedCueVoice extends _FakeVoicePromptService
    implements SpeechReadyCuePlayer {
  _GatedCueVoice(this.media);
  final _FakeLessonMediaService media;
  Map<String, Completer<void>> gates = {};
  Completer<void>? cue;
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    spoken.add('$locale:$text');
    await gates['$locale:$text']?.future;
  }

  @override
  Future<void> playSpeechReadyCue() async {
    media.events.add('cue');
    await cue?.future;
  }
}
