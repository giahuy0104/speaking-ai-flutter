import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/adaptive_voice_activity_detector.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_recording_endpoint_detector.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
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

  testWidgets('system Back cannot leave an unfinished Today session', (
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
    final voice = _BlockingExitVoicePromptService();
    addTearDown(media.close);
    addTearDown(voice.release);
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
    await tester.pump();
    await voice.exitPromptStarted.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.byType(VocabularyPracticeScreen), findsOneWidget);
    expect(find.text(VocabularyFlowV3.finishActiveGroupFirst), findsOneWidget);
    expect(await sessionStore.readActive(), isNotNull);
    expect(result, isNull);

    voice.release();
    await tester.pumpAndSettle();
  });
}

class _FakeLessonMediaService extends LessonMediaService {
  bool recording = false;
  int startCalls = 0;
  int stopCalls = 0;
  final StreamController<double> amplitudes =
      StreamController<double>.broadcast(sync: true);

  @override
  Stream<double> get recordingAmplitudeDbfs => amplitudes.stream;

  @override
  Future<void> prepareSelectedLessonOutput() async {}

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

class _BlockingExitVoicePromptService implements VoicePromptService {
  final Completer<void> exitPromptStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();

  @override
  Future<void> dispose() async => release();

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      speakAndWait(text, locale: locale);

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    if (text != VocabularyFlowV3.finishActiveGroupFirst) return;
    if (!exitPromptStarted.isCompleted) exitPromptStarted.complete();
    await _release.future;
  }

  @override
  Future<void> stop() async {}

  void release() {
    if (!_release.isCompleted) _release.complete();
  }
}
