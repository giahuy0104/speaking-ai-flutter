import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_session_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_practice_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadGoldenFonts);

  testWidgets('review practice HOMI stage at 390x844', (tester) async {
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
      english: 'At noon.',
      vietnamese: 'Buổi trưa.',
      collection: VocabularyCollection.review,
      source: VocabularySource.topicCore,
    );
    final session = await sessionStore.prepareReview(store);
    final media = _GoldenLessonMediaService();
    addTearDown(media.close);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: VocabularyPracticeScreen(
          language: DisplayLanguage.vietnamese,
          childAge: 6,
          session: session!,
          store: store,
          sessionStore: sessionStore,
          mediaService: media,
          attemptEvaluator: const RecordedAttemptEvaluator(),
          voicePromptService: const _GoldenVoicePromptService(),
          samplePause: Duration.zero,
          autoStart: false,
        ),
      ),
    );
    await tester.pump();
    final context = tester.element(find.byType(VocabularyPracticeScreen));
    await tester.runAsync(() async {
      await Future.wait<void>(<Future<void>>[
        precacheImage(
          const AssetImage(
            'assets/images/vocabulary/practice-homi-background.png',
          ),
          context,
        ),
        precacheImage(
          const AssetImage('assets/images/mascot/penguin-listen.png'),
          context,
        ),
      ]);
    });
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(VocabularyPracticeScreen),
      matchesGoldenFile('goldens/vocabulary-practice-homi-390x844.png'),
    );
  });

  testWidgets('parent-added journey uses the welcoming HOMI', (tester) async {
    await _pumpJourney(tester, cardKey: 'vocabulary-family-card');

    await expectLater(
      find.byType(VocabularyHomeScreen),
      matchesGoldenFile('goldens/vocabulary-family-homi-390x844.png'),
    );
  });

  testWidgets('stars journey uses the singing HOMI', (tester) async {
    await _pumpJourney(tester, cardKey: 'vocabulary-stars-card');

    await expectLater(
      find.byType(VocabularyHomeScreen),
      matchesGoldenFile('goldens/vocabulary-stars-homi-390x844.png'),
    );
  });
}

Future<void> _pumpJourney(
  WidgetTester tester, {
  required String cardKey,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final now = DateTime(2026, 9, 16);
  final store = _GoldenVocabularyStore(<VocabularyEntry>[
    VocabularyEntry(
      id: 'family-one',
      word: 'Good morning.',
      meaning: 'Chào buổi sáng.',
      addedAt: now,
      collection: VocabularyCollection.saved,
      source: VocabularySource.parent,
      parentState: ParentVocabularyState.unlocked,
    ),
    VocabularyEntry(
      id: 'star-one',
      word: 'You are amazing!',
      meaning: 'Con thật tuyệt vời!',
      addedAt: now,
      collection: VocabularyCollection.star,
      source: VocabularySource.topicCore,
      sourceSentenceId: 'S1',
      correctAudioPath: '/audio/star-one.m4a',
    ),
    VocabularyEntry(
      id: 'family-waiting',
      word: 'Brush your teeth.',
      meaning: 'Đánh răng.',
      addedAt: now.add(const Duration(minutes: 1)),
      collection: VocabularyCollection.saved,
      source: VocabularySource.parent,
      parentState: ParentVocabularyState.waiting,
    ),
  ]);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: DisplayLanguageScope(
        language: DisplayLanguage.vietnamese,
        child: VocabularyHomeScreen(
          isReady: true,
          store: store,
          voicePromptService: const _GoldenVoicePromptService(),
          onReturnToConversation: _noop,
          onHistory: _noop,
          onSettings: _noop,
        ),
      ),
    ),
  );
  await tester.pump();
  final context = tester.element(find.byType(VocabularyHomeScreen));
  await tester.runAsync(() async {
    await Future.wait<void>(
      const <AssetImage>[
        AssetImage('assets/images/learning-minimal-sky-background-option2.png'),
        AssetImage('assets/images/mascot/penguin-avatar.png'),
        AssetImage('assets/images/mascot/penguin-wave.png'),
        AssetImage('assets/images/mascot/penguin-sing.png'),
        AssetImage('assets/images/topics/my-family.jpg'),
        AssetImage('assets/images/vocabulary/golden-star.png'),
        AssetImage('assets/images/vocabulary/review-book.png'),
      ].map((provider) => precacheImage(provider, context)),
    );
  });
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(cardKey)));
  await tester.pumpAndSettle();
  if (cardKey == 'vocabulary-family-card') {
    expect(find.byKey(const Key('vocabulary-today-view')), findsNothing);
    expect(find.byKey(const Key('vocabulary-waiting-queue')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('vocabulary-waiting-queue'))).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey<String>('vocabulary-family-saved-content'),
              ),
            )
            .dy,
      ),
    );
  }
}

void _noop() {}

Future<void> _loadGoldenFonts() async {
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await Future.wait<void>(<Future<void>>[roboto.load(), materialIcons.load()]);
}

class _GoldenLessonMediaService extends LessonMediaService {
  final StreamController<double> _amplitudes =
      StreamController<double>.broadcast(sync: true);

  @override
  Stream<double> get recordingAmplitudeDbfs => _amplitudes.stream;

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
  }) async {}

  @override
  Future<LessonRecording> stopRecording() async => const LessonRecording(
    filePath: '/recordings/golden.m4a',
    duration: Duration(seconds: 2),
  );

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> stopPlayback() async {}

  Future<void> close() => _amplitudes.close();
}

class _GoldenVocabularyStore extends VocabularyStore {
  _GoldenVocabularyStore(this.entries);

  List<VocabularyEntry> entries;

  @override
  Future<List<VocabularyEntry>> read() async => entries;

  @override
  Future<void> write(List<VocabularyEntry> value) async {
    entries = List<VocabularyEntry>.of(value);
  }
}

class _GoldenVoicePromptService implements VoicePromptService {
  const _GoldenVoicePromptService();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> stop() async {}
}
