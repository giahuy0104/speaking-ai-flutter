import 'dart:async';
import 'dart:collection';

import 'package:ai_speaking_flutter_app/core/audio/audio_gain.dart';
import 'dart:convert';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/application/vocabulary_audio_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/application/vocabulary_fixed_prompt_audio_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_session_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_dictionary.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_flow_v3.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'touch back changes UI immediately and cancels old audio queue',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final audio = _BlockingVocabularyAudioService();
      final store = _MemoryVocabularyStore([
        for (final word in ['Apple', 'Banana'])
          VocabularyEntry(
            id: word,
            word: word,
            meaning: 'Nghĩa $word',
            addedAt: DateTime(2026, 9, 10),
            status: VocabularyLearningStatus.learnedWell,
            source: VocabularySource.parent,
            parentState: ParentVocabularyState.unlocked,
          ),
      ]);
      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: DisplayLanguageScope(
              language: DisplayLanguage.vietnamese,
              child: VocabularyHomeScreen(
                isReady: true,
                store: store,
                mediaService: _ImmediateLessonMediaService(),
                voicePromptService: const _FakeVoicePromptService(),
                vocabularyAudioService: audio,
                fixedPromptAudioService:
                    const _UnavailableFixedPromptAudioService(),
                onReturnToConversation: () {},
                onHistory: () {},
                onSettings: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vocabulary-family-card')));
      await tester.pumpAndSettle();
      final play = find.byKey(
        const ValueKey<String>('vocabulary-family-action'),
      );
      await tester.ensureVisible(play);
      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(audio.spoken, ['en-US:Apple']);
      expect(
        (registry.controller! as ActiveLearningVoiceContext).mainVoicePrompt,
        MasterNavigationContract.coreControlPrompt,
      );
      final back = find.byKey(const Key('vocabulary-home-back-button'));
      await tester.ensureVisible(back);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vocabulary-family-card')), findsOneWidget);
      expect(audio.stopCalls, 1);
      // Simulate a slow platform stop. Neither UI nor the next item waits on it.
      audio.stopGate.complete();
      await tester.pumpAndSettle();
      expect(audio.spoken, ['en-US:Apple']);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('leaving the vocabulary tab stops active collection audio', (
    tester,
  ) async {
    final active = ValueNotifier<bool>(true);
    final audio = _BlockingVocabularyAudioService();
    addTearDown(active.dispose);
    addTearDown(() {
      if (!audio.stopGate.isCompleted) audio.stopGate.complete();
      if (!audio.speechGate.isCompleted) audio.speechGate.complete();
    });
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      VocabularyEntry(
        id: 'Apple',
        word: 'Apple',
        meaning: 'Quả táo',
        addedAt: DateTime(2026, 9, 10),
        status: VocabularyLearningStatus.learnedWell,
        source: VocabularySource.parent,
        parentState: ParentVocabularyState.unlocked,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, isActive, _) => DisplayLanguageScope(
            language: DisplayLanguage.vietnamese,
            child: VocabularyHomeScreen(
              isReady: true,
              isActive: isActive,
              store: store,
              mediaService: _ImmediateLessonMediaService(),
              voicePromptService: const _FakeVoicePromptService(),
              vocabularyAudioService: audio,
              fixedPromptAudioService:
                  const _UnavailableFixedPromptAudioService(),
              onReturnToConversation: () {},
              onHistory: () {},
              onSettings: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();
    final play = find.byKey(const Key('vocabulary-family-action'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(audio.spoken, ['en-US:Apple']);

    active.value = false;
    await tester.pump();

    expect(audio.stopCalls, 1);
    expect(find.byKey(const Key('vocabulary-family-card')), findsOneWidget);
    audio.stopGate.complete();
    await tester.pumpAndSettle();
    expect(audio.spoken, ['en-US:Apple']);
  });

  testWidgets('collection playback highlights and follows an offscreen entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = _SteppedVocabularyAudioService();
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      for (var index = 0; index < 10; index++)
        VocabularyEntry(
          id: 'entry-$index',
          word: 'Word $index',
          meaning: 'Nghĩa $index',
          addedAt: DateTime(2026, 9, index + 1),
          status: VocabularyLearningStatus.learnedWell,
          source: VocabularySource.parent,
          parentState: ParentVocabularyState.unlocked,
        ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            mediaService: _ImmediateLessonMediaService(),
            voicePromptService: const _FakeVoicePromptService(),
            vocabularyAudioService: audio,
            fixedPromptAudioService:
                const _UnavailableFixedPromptAudioService(),
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();
    final play = find.byKey(const Key('vocabulary-family-action'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await _pumpUntil(tester, () => audio.spoken.length == 1);

    for (var completedSpeech = 1; completedSpeech < 9; completedSpeech++) {
      audio.completeCurrentSpeech();
      await _pumpUntil(
        tester,
        () => audio.spoken.length == completedSpeech + 1,
      );
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final highlight = tester.widget<AnimatedContainer>(
      find.byKey(const Key('vocabulary-entry-highlight-entry-4')),
    );
    expect((highlight.decoration! as BoxDecoration).border, isNotNull);
    final rect = tester.getRect(find.text('Word 4'));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));

    await tester.pumpWidget(const SizedBox.shrink());
    audio.stop();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible active entry does not trigger a redundant scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = _SteppedVocabularyAudioService();
    addTearDown(audio.stop);
    await _mountAutoFollowHome(
      tester,
      audio: audio,
      entries: <VocabularyEntry>[
        VocabularyEntry(
          id: 'visible-entry',
          word: 'Visible word',
          meaning: 'Nghĩa đang hiện',
          addedAt: DateTime(2026, 9, 1),
          status: VocabularyLearningStatus.learnedWell,
          source: VocabularySource.parent,
          parentState: ParentVocabularyState.unlocked,
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();
    final entry = find.byKey(
      const Key('vocabulary-entry-highlight-visible-entry'),
    );
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final initialOffset = scrollView.controller!.position.pixels;
    final initialRect = tester.getRect(entry);
    expect(initialRect.top, greaterThanOrEqualTo(0));
    expect(
      initialRect.bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );

    await tester.tap(find.byKey(const Key('vocabulary-action-visible-entry')));
    await _pumpUntil(tester, () => audio.spoken.length == 1);
    await tester.pump(const Duration(milliseconds: 300));

    expect(scrollView.controller!.position.pixels, closeTo(initialOffset, 1));
    final highlight = tester.widget<AnimatedContainer>(entry);
    expect((highlight.decoration! as BoxDecoration).border, isNotNull);
  });

  for (final routeLoss in <bool>[false, true]) {
    final interruption = routeLoss ? 'route loss' : 'MAIN';
    testWidgets('$interruption cancels an in-flight vocabulary auto-follow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final audio = _SteppedVocabularyAudioService();
      addTearDown(audio.stop);
      await _mountAutoFollowHome(
        tester,
        entries: _learnedParentEntries(10),
        audio: audio,
        registry: registry,
      );
      await tester.tap(find.byKey(const Key('vocabulary-family-card')));
      await tester.pumpAndSettle();
      final play = find.byKey(const Key('vocabulary-family-action'));
      await tester.ensureVisible(play);
      await tester.tap(play);
      await _pumpUntil(tester, () => audio.spoken.length == 1);
      await tester.pump(const Duration(milliseconds: 300));
      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 1000),
      );
      await tester.pump();

      while (audio.spoken.length < 9 &&
          !scrollView.controller!.position.isScrollingNotifier.value) {
        final nextSpeechCount = audio.spoken.length + 1;
        audio.completeCurrentSpeech();
        await _pumpUntil(tester, () => audio.spoken.length == nextSpeechCount);
        await tester.pump();
      }
      expect(scrollView.controller!.position.isScrollingNotifier.value, isTrue);
      final interruptedOffset = scrollView.controller!.position.pixels;
      final activeIndex = (audio.spoken.length - 1) ~/ 2;

      if (routeLoss) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        return;
      }

      await registry.pauseForMainAssistant();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        scrollView.controller!.position.pixels,
        closeTo(interruptedOffset, 1),
      );
      final highlight = tester.widget<AnimatedContainer>(
        find.byKey(Key('vocabulary-entry-highlight-entry-$activeIndex')),
      );
      expect((highlight.decoration! as BoxDecoration).border, isNull);
    });
  }

  testWidgets('stale family auto-follow cannot move Stars or Review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = _SteppedVocabularyAudioService();
    addTearDown(audio.stop);
    await _mountAutoFollowHome(
      tester,
      audio: audio,
      entries: <VocabularyEntry>[
        ..._learnedParentEntries(10, idPrefix: 'family', wordPrefix: 'Family'),
        VocabularyEntry(
          id: 'star-entry',
          word: 'Star word',
          meaning: 'Từ ngôi sao',
          addedAt: DateTime(2026, 9, 20),
          collection: VocabularyCollection.star,
          status: VocabularyLearningStatus.learnedWell,
          source: VocabularySource.topicCore,
          correctAudioPath: '/tmp/star-entry.wav',
        ),
        VocabularyEntry(
          id: 'review-entry',
          word: 'Review word',
          meaning: 'Từ cần luyện',
          addedAt: DateTime(2026, 9, 21),
          collection: VocabularyCollection.review,
          status: VocabularyLearningStatus.needsPractice,
          source: VocabularySource.topicCore,
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();
    final play = find.byKey(const Key('vocabulary-family-action'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await _pumpUntil(tester, () => audio.spoken.length == 1);
    await tester.pump(const Duration(milliseconds: 300));
    final familyScrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 1000),
    );
    await tester.pump();
    while (audio.spoken.length < 9 &&
        !familyScrollView.controller!.position.isScrollingNotifier.value) {
      final nextSpeechCount = audio.spoken.length + 1;
      audio.completeCurrentSpeech();
      await _pumpUntil(tester, () => audio.spoken.length == nextSpeechCount);
      await tester.pump();
    }
    expect(
      familyScrollView.controller!.position.isScrollingNotifier.value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('vocabulary-home-back-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-stars-card')));
    await tester.pumpAndSettle();
    final starsScrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final starsOffset = starsScrollView.controller!.position.pixels;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      starsScrollView.controller!.position.pixels,
      closeTo(starsOffset, 1),
    );
    final starHighlight = tester.widget<AnimatedContainer>(
      find.byKey(const Key('vocabulary-entry-highlight-star-entry')),
    );
    expect((starHighlight.decoration! as BoxDecoration).border, isNull);

    await tester.tap(find.byKey(const Key('vocabulary-home-back-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-review-card')));
    await tester.pumpAndSettle();
    final reviewScrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final reviewOffset = reviewScrollView.controller!.position.pixels;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      reviewScrollView.controller!.position.pixels,
      closeTo(reviewOffset, 1),
    );
    final reviewHighlight = tester.widget<AnimatedContainer>(
      find.byKey(const Key('vocabulary-entry-highlight-review-entry')),
    );
    expect((reviewHighlight.decoration! as BoxDecoration).border, isNull);
  });

  testWidgets('collection playback does not reclaim a completed user drag', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = _SteppedVocabularyAudioService();
    addTearDown(audio.stop);
    await _mountAutoFollowHome(
      tester,
      entries: _learnedParentEntries(10),
      audio: audio,
    );
    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();
    final play = find.byKey(const Key('vocabulary-family-action'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await _pumpUntil(tester, () => audio.spoken.length == 1);
    await tester.pump(const Duration(milliseconds: 300));

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final followedOffset = scrollView.controller!.position.pixels;
    expect(followedOffset, greaterThan(200));

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 1000),
    );
    await tester.pump();
    final userOffset = scrollView.controller!.position.pixels;
    expect(userOffset, lessThan(followedOffset));

    await tester.pump(const Duration(milliseconds: 400));
    expect(scrollView.controller!.position.pixels, closeTo(userOffset, 1));

    for (var completedSpeech = 1; completedSpeech < 9; completedSpeech++) {
      audio.completeCurrentSpeech();
      await _pumpUntil(
        tester,
        () => audio.spoken.length == completedSpeech + 1,
      );
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(scrollView.controller!.position.pixels, greaterThan(userOffset));
    final nextRect = tester.getRect(find.text('Word 4'));
    expect(nextRect.top, greaterThanOrEqualTo(0));
    expect(nextRect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
  });

  testWidgets('collection clears its highlight before waiting for a choice', (
    tester,
  ) async {
    final audio = _SteppedVocabularyAudioService();
    final choiceStarted = Completer<void>();
    final choiceGate = Completer<void>();
    addTearDown(() {
      if (!choiceGate.isCompleted) choiceGate.complete();
      audio.stop();
    });
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      VocabularyEntry(
        id: 'entry-1',
        word: 'Apple',
        meaning: 'Quả táo',
        addedAt: DateTime(2026, 9, 1),
        status: VocabularyLearningStatus.learnedWell,
        source: VocabularySource.parent,
        parentState: ParentVocabularyState.unlocked,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            mediaService: _ImmediateLessonMediaService(),
            voicePromptService: const _FakeVoicePromptService(),
            vocabularyAudioService: audio,
            fixedPromptAudioService:
                const _UnavailableFixedPromptAudioService(),
            onRequestVoiceChoice:
                ({noSpeechRetryPrompt, noSpeechExitPrompt}) async {
                  if (!choiceStarted.isCompleted) choiceStarted.complete();
                  await choiceGate.future;
                },
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();
    final play = find.byKey(const Key('vocabulary-family-action'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await _pumpUntil(tester, () => audio.spoken.length == 1);
    audio.completeCurrentSpeech();
    await _pumpUntil(tester, () => audio.spoken.length == 2);
    audio.completeCurrentSpeech();
    await _pumpUntil(tester, () => choiceStarted.isCompleted);
    await tester.pump(const Duration(milliseconds: 200));

    final highlight = tester.widget<AnimatedContainer>(
      find.byKey(const Key('vocabulary-entry-highlight-entry-1')),
    );
    expect((highlight.decoration! as BoxDecoration).border, isNull);
  });

  testWidgets(
    'opens the three vocabulary journeys from the redesigned home',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _MemoryVocabularyStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: DisplayLanguageScope(
            language: DisplayLanguage.vietnamese,
            child: VocabularyHomeScreen(
              isReady: true,
              store: store,
              voicePromptService: const _FakeVoicePromptService(),
              onReturnToConversation: () {},
              onHistory: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vocabulary-family-card')), findsOneWidget);
      expect(find.byKey(const Key('vocabulary-stars-card')), findsOneWidget);
      expect(find.byKey(const Key('vocabulary-review-card')), findsOneWidget);
      final familyCard = find.byKey(const Key('vocabulary-family-card'));
      final starsCard = find.byKey(const Key('vocabulary-stars-card'));
      final reviewCard = find.byKey(const Key('vocabulary-review-card'));
      final firstGap =
          tester.getTopLeft(starsCard).dy - tester.getBottomLeft(familyCard).dy;
      final secondGap =
          tester.getTopLeft(reviewCard).dy - tester.getBottomLeft(starsCard).dy;
      expect(firstGap, greaterThanOrEqualTo(24));
      expect(secondGap, closeTo(firstGap, 0.01));

      await tester.tap(find.byKey(const Key('vocabulary-family-card')));
      await tester.pumpAndSettle();
      expect(find.text('Ba mẹ đã thêm'), findsOneWidget);
      expect(
        find.byKey(const Key('vocabulary-back-to-journeys')),
        findsNothing,
      );
      final familyHeader = tester.widget<Container>(
        find.byKey(const Key('vocabulary-journey-detail-header')),
      );
      expect(
        (familyHeader.decoration! as BoxDecoration).color,
        AppColors.primaryNavy,
      );
      final waitingQueue = tester.widget<Container>(
        find.byKey(const Key('vocabulary-waiting-queue')),
      );
      final waitingDecoration = waitingQueue.decoration! as BoxDecoration;
      expect(waitingDecoration.color, AppColors.mintSoft);
      expect(waitingDecoration.border, isNotNull);
      expect(
        find.byKey(const Key('vocabulary-waiting-count-chip')),
        findsOneWidget,
      );
      final familyTitle = tester.widget<Text>(
        find.byKey(const Key('vocabulary-journey-title')),
      );
      expect(familyTitle.textAlign, TextAlign.center);

      await tester.tap(find.byKey(const Key('vocabulary-home-back-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vocabulary-stars-card')));
      await tester.pumpAndSettle();
      expect(find.text('Ngôi sao của bạn'), findsOneWidget);
      expect(
        (tester
                    .widget<Container>(
                      find.byKey(const Key('vocabulary-journey-detail-header')),
                    )
                    .decoration!
                as BoxDecoration)
            .color,
        AppColors.primaryNavy,
      );

      await tester.tap(find.byKey(const Key('vocabulary-home-back-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vocabulary-review-card')));
      await tester.pumpAndSettle();
      expect(find.text('Luyện lại'), findsOneWidget);
      expect(
        (tester
                    .widget<Container>(
                      find.byKey(const Key('vocabulary-journey-detail-header')),
                    )
                    .decoration!
                as BoxDecoration)
            .color,
        AppColors.primaryNavy,
      );
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'shows search in Stars and Review without exposing add controls',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 9, 16);
      final store = _MemoryVocabularyStore(<VocabularyEntry>[
        VocabularyEntry(
          id: 'star-card',
          word: 'Math',
          meaning: 'Môn Toán',
          addedAt: now,
          collection: VocabularyCollection.star,
          source: VocabularySource.topicCore,
          sourceSentenceId: 'S1',
          correctAudioPath: '/audio/star.wav',
        ),
        VocabularyEntry(
          id: 'review-card',
          word: 'At night',
          meaning: 'Buổi tối',
          addedAt: now,
          collection: VocabularyCollection.review,
          source: VocabularySource.topicCore,
          sourceSentenceId: 'S2',
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: DisplayLanguageScope(
            language: DisplayLanguage.vietnamese,
            child: VocabularyHomeScreen(
              isReady: true,
              store: store,
              voicePromptService: const _FakeVoicePromptService(),
              onReturnToConversation: () {},
              onHistory: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search-vocabulary-button')), findsNothing);
      expect(
        find.byKey(const Key('vocabulary-home-back-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('add-vocabulary-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('vocabulary-stars-card')));
      await tester.pumpAndSettle();

      expect(find.text('Ngôi sao của bạn'), findsOneWidget);
      expect(find.byKey(const Key('search-vocabulary-button')), findsNothing);
      expect(find.byKey(const Key('add-vocabulary-button')), findsNothing);
      expect(find.byKey(const Key('vocabulary-search-field')), findsOneWidget);
      expect(find.byKey(const Key('toggle-delete-vocabulary')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('vocabulary-stars-homi')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('vocabulary-entry-card-star-card')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('vocabulary-search-field')),
        'toán',
      );
      await tester.pump();
      expect(
        find.byKey(const Key('vocabulary-entry-card-star-card')),
        findsOneWidget,
      );
      final starsTitle = tester.widget<Text>(
        find.byKey(const Key('vocabulary-journey-title')),
      );
      expect(starsTitle.style?.fontSize, lessThanOrEqualTo(24));

      await tester.tap(find.byKey(const Key('vocabulary-home-back-button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('vocabulary-review-card')),
      );
      await tester.tap(find.byKey(const Key('vocabulary-review-card')));
      await tester.pumpAndSettle();

      expect(find.text('Luyện lại'), findsOneWidget);
      expect(find.byKey(const Key('search-vocabulary-button')), findsNothing);
      expect(find.byKey(const Key('add-vocabulary-button')), findsNothing);
      expect(find.byKey(const Key('vocabulary-search-field')), findsOneWidget);
      expect(find.byKey(const Key('toggle-delete-vocabulary')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('vocabulary-review-homi')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('vocabulary-entry-card-review-card')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('vocabulary-search-field')),
        'buổi tối',
      );
      await tester.pump();
      expect(
        find.byKey(const Key('vocabulary-entry-card-review-card')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('vocabulary-home-back-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vocabulary-family-card')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search-vocabulary-button')), findsNothing);
      expect(find.byKey(const Key('add-vocabulary-button')), findsOneWidget);
      expect(find.byKey(const Key('vocabulary-search-field')), findsOneWidget);
      expect(find.byKey(const Key('toggle-delete-vocabulary')), findsNothing);
      expect(find.byKey(const Key('add-vocabulary-action')), findsNothing);
      expect(find.text('Danh sách chờ'), findsOneWidget);
      expect(find.text('(0)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('vocabulary-family-homi')),
        findsOneWidget,
      );
    },
  );

  testWidgets('adds a Vietnamese vocabulary entry and persists it', (
    tester,
  ) async {
    final store = _MemoryVocabularyStore();
    final audioService = _RecordingVocabularyAudioService();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            voicePromptService: const _FakeVoicePromptService(),
            vocabularyAudioService: audioService,
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-vocabulary-button')));
    await tester.pumpAndSettle();

    expect(find.text('Thêm nội dung học'), findsOneWidget);
    expect(
      find.text('Có thể nhập bằng tiếng Anh hoặc tiếng Việt.'),
      findsOneWidget,
    );
    expect(find.text('Ví dụ:'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('add-vocabulary-field')),
      'quả táo',
    );
    await tester.pump();
    final confirm = find.byKey(const Key('confirm-add-vocabulary'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('confirm-vocabulary-suggestions')));
    await tester.pumpAndSettle();

    expect(store.entries.first.word, 'Apple');
    expect(store.entries.first.meaning, 'Quả táo');
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Quả táo'), findsOneWidget);
    expect(audioService.prefetched, <String>['en-US:Apple', 'vi-VN:Quả táo']);
  });

  testWidgets('rejects content found anywhere in the Topic curriculum', (
    tester,
  ) async {
    final store = _MemoryVocabularyStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            voicePromptService: const _FakeVoicePromptService(),
            translator: (_) async => const VocabularyTranslation(
              englishText: 'I will be a doctor.',
              vietnameseText: 'Con sẽ là bác sĩ.',
            ),
            curriculumDuplicateChecker: (candidate) async =>
                candidate.englishText == 'I will be a doctor.',
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-vocabulary-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-vocabulary-field')),
      'Con sẽ là bác sĩ',
    );
    await tester.pump();
    final confirm = find.byKey(const Key('confirm-add-vocabulary'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(store.entries, isEmpty);
    expect(
      find.text(
        'Nội dung này đã có trong phần Chủ đề. Bạn thêm nội dung khác nhé.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('confirm-vocabulary-suggestions')),
      findsNothing,
    );
  });

  testWidgets('keeps search separate from the dedicated add flow', (
    tester,
  ) async {
    final store = _MemoryVocabularyStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            voicePromptService: const _FakeVoicePromptService(),
            translator: (_) async => const VocabularyTranslation(
              englishText: 'Cat',
              vietnameseText: 'Con mèo',
            ),
            suggestionProvider: (_, _) async => const <VocabularyTranslation>[
              VocabularyTranslation(
                englishText: 'It is a cat.',
                vietnameseText: 'Đó là con mèo.',
              ),
            ],
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('vocabulary-search-field')),
      'con mèo',
    );
    await tester.pump();

    expect(find.byKey(const Key('add-vocabulary-from-search')), findsNothing);
    expect(find.byKey(const Key('clear-vocabulary-search')), findsOneWidget);
    expect(find.byKey(const Key('add-vocabulary-action')), findsNothing);
    expect(find.byKey(const Key('add-vocabulary-button')), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.byKey(const Key('add-vocabulary-field')), findsNothing);

    await tester.tap(find.byKey(const Key('add-vocabulary-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-vocabulary-field')),
      'con mèo',
    );
    await tester.pump();
    final confirmAdd = find.byKey(const Key('confirm-add-vocabulary'));
    await tester.ensureVisible(confirmAdd);
    await tester.tap(confirmAdd);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Cat'), findsOneWidget);
    expect(find.text('It is a cat.'), findsOneWidget);
    expect(
      find.byKey(const Key('vocabulary-minhqnd-attribution')),
      findsOneWidget,
    );
    final editFirstSuggestion = find.byKey(
      const Key('edit-vocabulary-suggestion-0'),
    );
    expect(editFirstSuggestion, findsOneWidget);
    await tester.ensureVisible(editFirstSuggestion);
    await tester.tap(editFirstSuggestion);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('vocabulary-suggestion-english-0')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    await tester.enterText(
      find.byKey(const Key('vocabulary-suggestion-english-0')),
      'Kitten',
    );
    await tester.enterText(
      find.byKey(const Key('vocabulary-suggestion-vietnamese-0')),
      'Mèo con',
    );
    await tester.pump();
    final saveFirstSuggestion = find.byKey(
      const Key('save-vocabulary-suggestion-0'),
    );
    expect(saveFirstSuggestion, findsOneWidget);
    await tester.ensureVisible(saveFirstSuggestion);
    await tester.tap(saveFirstSuggestion);
    await tester.pump();
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(
              const ValueKey<String>('select-vocabulary-suggestion-0'),
            ),
          )
          .value,
      isTrue,
    );
    expect(find.byKey(const Key('save-vocabulary-suggestion-0')), findsNothing);
    expect(find.text('It is a cat.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-vocabulary-suggestions')));
    await tester.pumpAndSettle();

    expect(store.entries, hasLength(1));
    expect(store.entries.single.word, 'Kitten');
    expect(store.entries.single.meaning, 'Mèo con');
    expect(find.byKey(const Key('add-vocabulary-from-search')), findsNothing);
  });

  testWidgets('shows distinct dictionary meanings for the parent to choose', (
    tester,
  ) async {
    final store = _MemoryVocabularyStore();
    final audioService = _RecordingVocabularyAudioService();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            voicePromptService: const _FakeVoicePromptService(),
            vocabularyAudioService: audioService,
            dictionaryProvider: _FakeVocabularyDictionaryProvider(
              result: const VocabularyDictionaryResult(
                english: 'mad',
                definitions: <VocabularyDictionaryDefinition>[
                  VocabularyDictionaryDefinition(
                    vietnamese: 'Tức giận',
                    partOfSpeech: 'Tính từ',
                  ),
                  VocabularyDictionaryDefinition(
                    vietnamese: 'Điên rồ',
                    partOfSpeech: 'Tính từ',
                  ),
                  VocabularyDictionaryDefinition(
                    vietnamese: 'Cuồng nhiệt',
                    partOfSpeech: 'Tính từ',
                  ),
                ],
              ),
            ),
            suggestionProvider: (_, _) async => const <VocabularyTranslation>[],
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-vocabulary-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-vocabulary-field')),
      'mad',
    );
    await tester.pump();
    final confirm = find.byKey(const Key('confirm-add-vocabulary'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const Key('confirm-vocabulary-suggestions')),
      findsOneWidget,
    );
    expect(find.text('Đã chọn'), findsNothing);
    expect(find.textContaining('Chọn tối đa'), findsNothing);
    expect(find.textContaining('Nhấn biểu tượng bút'), findsNothing);
    final selectedSuggestionCard = tester.widget<Container>(
      find.byKey(const ValueKey<String>('vocabulary-suggestion-0')),
    );
    final selectedSuggestionDecoration =
        selectedSuggestionCard.decoration! as BoxDecoration;
    final selectedSuggestionBorder =
        selectedSuggestionDecoration.border! as Border;
    expect(selectedSuggestionBorder.top.color, AppColors.primaryNavy);
    expect(selectedSuggestionBorder.top.width, 1.5);
    for (var index = 0; index < 3; index++) {
      expect(
        find.byKey(ValueKey<String>('vocabulary-suggestion-$index')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('vocabulary-suggestion-3')),
      findsNothing,
    );
    expect(find.text('Tức giận'), findsOneWidget);
    expect(find.text('Điên rồ'), findsOneWidget);
    expect(find.text('I am mad.'), findsOneWidget);

    for (final index in <int>[1, 2]) {
      final checkbox = find.byKey(
        ValueKey<String>('select-vocabulary-suggestion-$index'),
      );
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pump();
    }
    expect(find.text('3/3 đã chọn'), findsOneWidget);
    for (var index = 0; index < 3; index++) {
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(
                ValueKey<String>('select-vocabulary-suggestion-$index'),
              ),
            )
            .value,
        isTrue,
      );
    }
    await tester.tap(find.byKey(const Key('confirm-vocabulary-suggestions')));
    await tester.pumpAndSettle();
    expect(store.entries, hasLength(3));
  });

  testWidgets('shows lesson sentences in Stars and Review collections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 8, 14);
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      VocabularyEntry(
        id: 'star',
        word: "I'm An",
        meaning: 'Con là An',
        addedAt: now,
        collection: VocabularyCollection.star,
        source: VocabularySource.topicCore,
        sourceSentenceId: 'S1',
        correctAudioPath: '/audio/star.wav',
      ),
      VocabularyEntry(
        id: 'review',
        word: 'This is my bag',
        meaning: 'Đây là cặp của con',
        addedAt: now,
        collection: VocabularyCollection.review,
        source: VocabularySource.topicCore,
        sourceSentenceId: 'S2',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            voicePromptService: const _FakeVoicePromptService(),
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 nội dung yêu thích'), findsOneWidget);
    expect(find.text('1 nội dung cần ôn'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vocabulary-stars-card')));
    await tester.pumpAndSettle();
    expect(find.text("I'm An"), findsOneWidget);
    expect(find.text('This is my bag'), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('vocabulary-order-star')),
          )
          .data,
      '1',
    );

    await tester.tap(find.byKey(const Key('vocabulary-home-back-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('vocabulary-review-card')));
    await tester.tap(find.byKey(const Key('vocabulary-review-card')));
    await tester.pumpAndSettle();
    expect(find.text('This is my bag'), findsOneWidget);
    expect(find.text("I'm An"), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('vocabulary-order-review')),
          )
          .data,
      '1',
    );
  });

  testWidgets('refreshes collection counts after a lesson saves a sentence', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'innotrik.vocabulary.v1': jsonEncode(<Object>[]),
    });
    const store = VocabularyStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            voicePromptService: const _FakeVoicePromptService(),
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 nội dung yêu thích'), findsOneWidget);

    await store.upsertLessonSentence(
      lessonCode: 'A035_T01_L01',
      sentenceId: 'S1',
      english: "I'm An",
      vietnamese: 'Con là An',
      collection: VocabularyCollection.star,
      correctAudioPath: '/audio/star.wav',
    );
    await tester.pumpAndSettle();

    expect(find.text('1 nội dung yêu thích'), findsOneWidget);
  });

  testWidgets('Parent Added is oldest-first without legacy learning labels', (
    tester,
  ) async {
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      VocabularyEntry(
        id: 'new',
        word: 'New content',
        meaning: 'Nội dung mới',
        addedAt: DateTime(2026, 9, 15),
        source: VocabularySource.parent,
        status: VocabularyLearningStatus.learnedWell,
        parentState: ParentVocabularyState.unlocked,
      ),
      VocabularyEntry(
        id: 'old',
        word: 'Old content',
        meaning: 'Nội dung cũ',
        addedAt: DateTime(2026, 9, 14),
        source: VocabularySource.parent,
        status: VocabularyLearningStatus.learnedWell,
        parentState: ParentVocabularyState.unlocked,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            voicePromptService: const _FakeVoicePromptService(),
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Old content')).dy,
      lessThan(tester.getTopLeft(find.text('New content')).dy),
    );
    expect(find.text('Đã học tốt'), findsNothing);
    expect(find.text('2 nội dung đã lưu'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('vocabulary-order-old')),
          )
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('vocabulary-order-new')),
          )
          .data,
      '2',
    );

    await tester.enterText(
      find.byKey(const Key('vocabulary-search-field')),
      'New content',
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('vocabulary-order-new')),
          )
          .data,
      '1',
    );
    expect(
      find.byKey(const ValueKey<String>('vocabulary-order-old')),
      findsNothing,
    );
  });

  testWidgets('edits both English and Vietnamese in the waiting queue', (
    tester,
  ) async {
    final addedAt = DateTime(2026, 9, 16, 10);
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      VocabularyEntry(
        id: 'waiting-edit',
        word: 'What happened?',
        meaning: 'Chuyện gì đã xảy ra?',
        addedAt: addedAt,
        source: VocabularySource.parent,
        parentState: ParentVocabularyState.waiting,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            voicePromptService: const _FakeVoicePromptService(),
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();

    final editButton = find.byKey(
      const ValueKey<String>('edit-waiting-waiting-edit'),
    );
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    final englishField = find.byKey(const Key('edit-vocabulary-english-field'));
    final vietnameseField = find.byKey(
      const Key('edit-vocabulary-vietnamese-field'),
    );
    expect(find.text('Sửa nội dung'), findsOneWidget);
    expect(
      find.text('Có thể nhập bằng tiếng Anh hoặc tiếng Việt.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(englishField).controller?.text,
      'What happened?',
    );
    expect(
      tester.widget<TextField>(vietnameseField).controller?.text,
      'Chuyện gì đã xảy ra?',
    );

    await tester.enterText(englishField, 'What is happening?');
    await tester.enterText(vietnameseField, 'Chuyện gì đang xảy ra?');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-edit-vocabulary')));
    await tester.pumpAndSettle();

    expect(store.entries.single.word, 'What is happening?');
    expect(store.entries.single.meaning, 'Chuyện gì đang xảy ra?');
    expect(store.entries.single.parentState, ParentVocabularyState.waiting);
    expect(store.entries.single.addedAt, addedAt);
    expect(find.text('What is happening?'), findsOneWidget);
    expect(find.text('Chuyện gì đang xảy ra?'), findsOneWidget);
  });

  testWidgets('announces the child voice at the start of every Star block', (
    tester,
  ) async {
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final voice = _RecordingVoicePromptService();
    final media = _ImmediateLessonMediaService();
    final now = DateTime(2026, 9, 15);
    final store = _MemoryVocabularyStore(
      List<VocabularyEntry>.generate(
        6,
        (index) => VocabularyEntry(
          id: 'star-$index',
          word: 'Sentence ${index + 1}',
          meaning: 'Câu ${index + 1}',
          addedAt: now.add(Duration(minutes: index)),
          earnedAt: now.add(Duration(minutes: index)),
          collection: VocabularyCollection.star,
          source: VocabularySource.topicCore,
          correctAudioPath: 'C:\\audio\\star-$index.wav',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ActiveLearningModuleScope(
          registry: registry,
          child: DisplayLanguageScope(
            language: DisplayLanguage.vietnamese,
            child: VocabularyHomeScreen(
              isReady: true,
              isActive: true,
              store: store,
              mediaService: media,
              voicePromptService: voice,
              recordingFinder: (path) async => path,
              fixedPromptAudioService:
                  const _UnavailableFixedPromptAudioService(),
              onReturnToConversation: () {},
              onHistory: () {},
              onSettings: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-stars-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-stars-action')));
    await _pumpUntil(tester, () => media.played.length == 5);
    await tester.pump();

    final childReplays = media.played.where(
      (clip) => clip.uri.path.toLowerCase().endsWith('.wav'),
    );
    expect(childReplays, isNotEmpty);
    expect(
      childReplays.map((clip) => clip.gainDb),
      everyElement(lessonRecordingPlaybackGainDb),
    );
    expect(
      voice.spokenTexts.where((text) => text == VocabularyFlowV3.starMyVoice),
      hasLength(1),
    );
    final next = await registry.execute(ActiveLearningCommand.nextItem);
    expect(next.wasHandled, isTrue);
    await _pumpUntil(tester, () => media.played.length == 6);
    await tester.pump();
    expect(
      voice.spokenTexts.where((text) => text == VocabularyFlowV3.starMyVoice),
      hasLength(2),
    );
  });

  testWidgets(
    'keeps a newly added parent entry silent until it has been learned',
    (tester) async {
      final store = _MemoryVocabularyStore();
      final voice = _RecordingVoicePromptService();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: DisplayLanguageScope(
            language: DisplayLanguage.vietnamese,
            child: VocabularyHomeScreen(
              isReady: true,
              store: store,
              voicePromptService: voice,
              translator: (input) async {
                expect(input, 'con mèo');
                return const VocabularyTranslation(
                  englishText: 'cat',
                  vietnameseText: 'con mèo',
                );
              },
              onReturnToConversation: () {},
              onHistory: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-vocabulary-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add-vocabulary-field')),
        'con mèo',
      );
      await tester.pump();
      final confirm = find.byKey(const Key('confirm-add-vocabulary'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('confirm-vocabulary-suggestions')));
      await tester.pumpAndSettle();

      expect(store.entries, hasLength(1));
      expect(store.entries.single.word, 'Cat');
      expect(store.entries.single.meaning, 'Con mèo');
      expect(find.text('Cat'), findsOneWidget);
      expect(find.text('Con mèo'), findsOneWidget);

      expect(find.byKey(const Key('vocabulary-today-view')), findsNothing);
      expect(find.byKey(const Key('vocabulary-waiting-queue')), findsOneWidget);
      expect(find.text('Danh sách chờ'), findsOneWidget);
      expect(find.text('(1)'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey<String>(
            'vocabulary-waiting-order-${store.entries.single.id}',
          ),
        ),
        findsOneWidget,
      );
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
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
      expect(voice.spokenTexts, isEmpty);
      expect(voice.locales, isEmpty);
    },
  );

  testWidgets('MAIN vocabulary commands open Review and Stars journeys', (
    tester,
  ) async {
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ActiveLearningModuleScope(
          registry: registry,
          child: DisplayLanguageScope(
            language: DisplayLanguage.vietnamese,
            child: VocabularyHomeScreen(
              isReady: true,
              isActive: true,
              store: _MemoryVocabularyStore(),
              voicePromptService: const _FakeVoicePromptService(),
              onReturnToConversation: () {},
              onHistory: () {},
              onSettings: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(registry.activeKind, ActiveLearningModuleKind.vocabulary);
    await registry.pauseForMainAssistant();
    expect(registry.isActiveModulePaused, isTrue);

    final review = await registry.execute(
      ActiveLearningCommand.vocabularyPracticeAgain,
    );
    await tester.pumpAndSettle();
    expect(review.wasHandled, isTrue);
    expect(find.text('Luyện lại'), findsOneWidget);

    final stars = await registry.execute(ActiveLearningCommand.vocabularyStars);
    await tester.pumpAndSettle();
    expect(stars.wasHandled, isTrue);
    expect(find.text('Ngôi sao của bạn'), findsOneWidget);
  });

  testWidgets(
    'MAIN interruption does not open a vocabulary choice microphone',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final prompt = _InterruptibleVoicePromptService();
      var choiceRequests = 0;
      addTearDown(registry.dispose);
      addTearDown(prompt.complete);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ActiveLearningModuleScope(
            registry: registry,
            child: DisplayLanguageScope(
              language: DisplayLanguage.vietnamese,
              child: VocabularyHomeScreen(
                isReady: true,
                isActive: true,
                store: _MemoryVocabularyStore(),
                mediaService: _ImmediateLessonMediaService(),
                voicePromptService: prompt,
                fixedPromptAudioService:
                    const _UnavailableFixedPromptAudioService(),
                onRequestVoiceChoice:
                    ({
                      String? noSpeechRetryPrompt,
                      String? noSpeechExitPrompt,
                    }) async {
                      choiceRequests++;
                    },
                onReturnToConversation: () {},
                onHistory: () {},
                onSettings: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        (await registry.execute(
          ActiveLearningCommand.vocabularyStars,
        )).wasHandled,
        isTrue,
      );
      await tester.pump();
      expect(prompt.started, isTrue);

      expect(await registry.pauseForMainAssistant(), isTrue);
      await tester.pumpAndSettle();

      expect(choiceRequests, 0);
    },
  );

  testWidgets('MAIN vocabulary prompt failure is handled and can retry', (
    tester,
  ) async {
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final prompt = _FailingJourneyVoicePromptService();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ActiveLearningModuleScope(
          registry: registry,
          child: DisplayLanguageScope(
            language: DisplayLanguage.vietnamese,
            child: VocabularyHomeScreen(
              isReady: true,
              isActive: true,
              store: _MemoryVocabularyStore(),
              mediaService: _ImmediateLessonMediaService(),
              voicePromptService: prompt,
              fixedPromptAudioService:
                  const _UnavailableFixedPromptAudioService(),
              onReturnToConversation: () {},
              onHistory: () {},
              onSettings: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    prompt.fail = true;
    await registry.execute(ActiveLearningCommand.vocabularyStars);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('Kết nối âm thanh H20 bị gián đoạn. Hãy thử lại.'),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    prompt.fail = false;
    await registry.execute(ActiveLearningCommand.vocabularyParentAdded);
    await tester.pumpAndSettle();
    expect(find.text('Ba mẹ đã thêm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'logical activation enables vocabulary commands before a visual page change',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final activationController = VocabularyActivationController();
      addTearDown(registry.dispose);
      addTearDown(activationController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ActiveLearningModuleScope(
            registry: registry,
            child: DisplayLanguageScope(
              language: DisplayLanguage.vietnamese,
              child: VocabularyHomeScreen(
                isReady: true,
                isActive: false,
                activationController: activationController,
                store: _MemoryVocabularyStore(),
                voicePromptService: const _FakeVoicePromptService(),
                onReturnToConversation: () {},
                onHistory: () {},
                onSettings: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(registry.activeKind, isNull);
      activationController.activate();

      expect(registry.activeKind, ActiveLearningModuleKind.vocabulary);
      final stars = await registry.execute(
        ActiveLearningCommand.vocabularyStars,
      );
      await tester.pumpAndSettle();
      expect(stars.wasHandled, isTrue);
      expect(find.text('Ngôi sao của bạn'), findsOneWidget);
    },
  );

  testWidgets(
    'Stars commits its checkpoint only after EN VI and child audio succeed',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final voice = _RecordingVoicePromptService();
      final media = _TransactionalLessonMediaService();
      final store = _MemoryVocabularyStore(<VocabularyEntry>[
        _starEntry('first'),
      ]);
      const sessions = VocabularySessionStore();
      addTearDown(registry.dispose);

      await _mountStarPlaybackHome(
        tester,
        registry: registry,
        voice: voice,
        media: media,
        store: store,
        entries: store.entries,
      );
      await tester.tap(find.byKey(const Key('vocabulary-stars-action')));
      await tester.pumpAndSettle();

      expect(
        voice.spokenTexts,
        containsAllInOrder(<String>['Word first', 'Nghĩa first']),
      );
      expect(media.playCalls, 1);
      expect(await sessions.readPlaybackCheckpoint('stars:ordered'), 1);
      expect(store.entries.single.correctAudioPath, isNotNull);
    },
  );

  testWidgets(
    'Stars repairs a missing recording without advancing its checkpoint',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final store = _MemoryVocabularyStore(<VocabularyEntry>[
        _starEntry('missing'),
      ]);
      final media = _TransactionalLessonMediaService();
      const sessions = VocabularySessionStore();
      addTearDown(registry.dispose);

      await _mountStarPlaybackHome(
        tester,
        registry: registry,
        store: store,
        media: media,
        entries: store.entries,
        recordingFinder: (_) async => null,
      );
      await tester.tap(find.byKey(const Key('vocabulary-stars-action')));
      await tester.pumpAndSettle();

      expect(store.entries.single.correctAudioPath, isNull);
      expect(store.entries.single.collection, VocabularyCollection.star);
      expect(media.prepareCalls, 0);
      expect(media.playCalls, 0);
      expect(await sessions.readPlaybackCheckpoint('stars:ordered'), 0);
      expect(
        find.text(
          'Bản ghi Ngôi sao này không còn khả dụng. Con hãy luyện lại nhé.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Stars reacquires the route and retries a failed child recording once',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final media = _TransactionalLessonMediaService(playFailures: 1);
      const sessions = VocabularySessionStore();
      addTearDown(registry.dispose);

      await _mountStarPlaybackHome(
        tester,
        registry: registry,
        media: media,
        entries: <VocabularyEntry>[_starEntry('retry')],
      );
      await tester.tap(find.byKey(const Key('vocabulary-stars-action')));
      await tester.pumpAndSettle();

      expect(media.playCalls, 2);
      expect(media.prepareCalls, greaterThanOrEqualTo(2));
      expect(await sessions.readPlaybackCheckpoint('stars:ordered'), 1);
    },
  );

  testWidgets('Stars retries route preparation at the same entry', (
    tester,
  ) async {
    final registry = ActiveLearningModuleRegistry();
    final media = _TransactionalLessonMediaService(prepareFailures: 1);
    const sessions = VocabularySessionStore();
    addTearDown(registry.dispose);

    await _mountStarPlaybackHome(
      tester,
      registry: registry,
      media: media,
      entries: <VocabularyEntry>[_starEntry('route-retry')],
    );
    await tester.tap(find.byKey(const Key('vocabulary-stars-action')));
    await tester.pumpAndSettle();

    expect(media.prepareCalls, 2);
    expect(media.playCalls, 1);
    expect(await sessions.readPlaybackCheckpoint('stars:ordered'), 1);
  });

  testWidgets(
    'Stars keeps the failed entry current and never skips to the next entry',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final voice = _RecordingVoicePromptService();
      final media = _TransactionalLessonMediaService(playFailures: 2);
      const sessions = VocabularySessionStore();
      addTearDown(registry.dispose);

      await _mountStarPlaybackHome(
        tester,
        registry: registry,
        voice: voice,
        media: media,
        entries: <VocabularyEntry>[
          _starEntry('failed'),
          _starEntry('must-not-play'),
        ],
      );
      await tester.tap(find.byKey(const Key('vocabulary-stars-action')));
      await tester.pumpAndSettle();

      expect(media.playCalls, 2);
      expect(voice.spokenTexts, isNot(contains('Word must-not-play')));
      expect(await sessions.readPlaybackCheckpoint('stars:ordered'), 0);
    },
  );

  testWidgets(
    'MAIN resume waits for cleanup and stale playback cannot checkpoint',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final firstPlay = Completer<void>();
      final resumedPlay = Completer<void>();
      final stopGate = Completer<void>();
      final media = _TransactionalLessonMediaService(
        playGates: Queue<Completer<void>>.of(<Completer<void>>[
          firstPlay,
          resumedPlay,
        ]),
        stopGate: stopGate,
      );
      const sessions = VocabularySessionStore();
      addTearDown(registry.dispose);
      addTearDown(() {
        if (!stopGate.isCompleted) stopGate.complete();
        if (!firstPlay.isCompleted) firstPlay.complete();
        if (!resumedPlay.isCompleted) resumedPlay.complete();
      });

      await _mountStarPlaybackHome(
        tester,
        registry: registry,
        media: media,
        entries: <VocabularyEntry>[_starEntry('resume')],
      );
      await tester.tap(find.byKey(const Key('vocabulary-stars-action')));
      await _pumpUntil(tester, () => media.playCalls == 1);

      final pausing = registry.pauseForMainAssistant();
      await tester.pump();
      final resume = await registry.execute(ActiveLearningCommand.resume);
      expect(resume.wasHandled, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(media.playCalls, 1);
      expect(await sessions.readPlaybackCheckpoint('stars:ordered'), 0);

      stopGate.complete();
      await _pumpUntil(tester, () => media.playCalls == 2);
      await pausing;
      expect(await sessions.readPlaybackCheckpoint('stars:ordered'), 0);

      resumedPlay.complete();
      await tester.pumpAndSettle();
      expect(await sessions.readPlaybackCheckpoint('stars:ordered'), 1);
    },
  );
}

Future<void> _mountStarPlaybackHome(
  WidgetTester tester, {
  required ActiveLearningModuleRegistry registry,
  required _TransactionalLessonMediaService media,
  required List<VocabularyEntry> entries,
  _MemoryVocabularyStore? store,
  _RecordingVoicePromptService? voice,
  Future<String?> Function(String path)? recordingFinder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: ActiveLearningModuleScope(
        registry: registry,
        child: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store ?? _MemoryVocabularyStore(entries),
            mediaService: media,
            voicePromptService: voice ?? _RecordingVoicePromptService(),
            fixedPromptAudioService:
                const _UnavailableFixedPromptAudioService(),
            recordingFinder: recordingFinder ?? (path) async => path,
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('vocabulary-stars-card')));
  await tester.pumpAndSettle();
}

VocabularyEntry _starEntry(String id) => VocabularyEntry(
  id: id,
  word: 'Word $id',
  meaning: 'Nghĩa $id',
  addedAt: DateTime(2026, 9, 25),
  earnedAt: DateTime(2026, 9, 25),
  collection: VocabularyCollection.star,
  status: VocabularyLearningStatus.learnedWell,
  source: VocabularySource.topicCore,
  starSlotId: 'slot:$id',
  correctAudioPath: 'C:\\recordings\\$id.wav',
);

Future<void> _mountAutoFollowHome(
  WidgetTester tester, {
  required List<VocabularyEntry> entries,
  required _SteppedVocabularyAudioService audio,
  ActiveLearningModuleRegistry? registry,
}) async {
  final app = MaterialApp(
    theme: buildAppTheme(),
    home: DisplayLanguageScope(
      language: DisplayLanguage.vietnamese,
      child: VocabularyHomeScreen(
        isReady: true,
        store: _MemoryVocabularyStore(entries),
        mediaService: _ImmediateLessonMediaService(),
        voicePromptService: const _FakeVoicePromptService(),
        vocabularyAudioService: audio,
        fixedPromptAudioService: const _UnavailableFixedPromptAudioService(),
        onReturnToConversation: () {},
        onHistory: () {},
        onSettings: () {},
      ),
    ),
  );
  await tester.pumpWidget(
    registry == null
        ? app
        : ActiveLearningModuleScope(registry: registry, child: app),
  );
  await tester.pumpAndSettle();
}

List<VocabularyEntry> _learnedParentEntries(
  int count, {
  String idPrefix = 'entry',
  String wordPrefix = 'Word',
}) => <VocabularyEntry>[
  for (var index = 0; index < count; index++)
    VocabularyEntry(
      id: '$idPrefix-$index',
      word: '$wordPrefix $index',
      meaning: 'Nghĩa $index',
      addedAt: DateTime(2026, 9, index + 1),
      status: VocabularyLearningStatus.learnedWell,
      source: VocabularySource.parent,
      parentState: ParentVocabularyState.unlocked,
    ),
];

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

class _MemoryVocabularyStore extends VocabularyStore {
  _MemoryVocabularyStore([List<VocabularyEntry>? entries])
    : entries = List.of(entries ?? const <VocabularyEntry>[]);

  List<VocabularyEntry> entries;

  @override
  Future<List<VocabularyEntry>> read() async => entries;

  @override
  Future<void> write(List<VocabularyEntry> value) async {
    entries = List<VocabularyEntry>.of(value);
  }
}

class _FakeVoicePromptService implements VoicePromptService {
  const _FakeVoicePromptService();

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _InterruptibleVoicePromptService implements VoicePromptService {
  final Completer<void> _speech = Completer<void>();
  bool started = false;

  void complete() {
    if (!_speech.isCompleted) _speech.complete();
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      speakAndWait(text, locale: locale);

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    started = true;
    await _speech.future;
  }

  @override
  Future<void> stop() async => complete();

  @override
  Future<void> dispose() async => complete();
}

class _FakeVocabularyDictionaryProvider
    implements VocabularyDictionaryProvider {
  const _FakeVocabularyDictionaryProvider({required this.result});

  final VocabularyDictionaryResult? result;

  @override
  Future<VocabularyDictionaryResult?> lookupEnglish(String text) async =>
      result;

  @override
  Uri ttsUri(String text, {required String locale}) =>
      Uri.parse('https://example.test/tts');

  @override
  void dispose() {}
}

class _RecordingVocabularyAudioService
    implements VocabularyContentAudioService {
  final List<String> prefetched = <String>[];

  @override
  Future<void> prefetch(String text, {required String locale}) async {
    prefetched.add('$locale:$text');
  }

  @override
  Future<VocabularyAudioSource> speakAndWait(
    String text, {
    required String locale,
  }) async => VocabularyAudioSource.nativeTts;

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}

class _UnavailableFixedPromptAudioService
    implements VocabularyFixedPromptAudioService {
  const _UnavailableFixedPromptAudioService();

  @override
  Future<bool> playAudioCodeIfAvailable(String audioCode) async => false;

  @override
  Future<bool> playPromptIfAvailable(String text) async => false;
}

class _BlockingVocabularyAudioService implements VocabularyContentAudioService {
  final spoken = <String>[];
  final stopGate = Completer<void>();
  final speechGate = Completer<void>();
  int stopCalls = 0;
  @override
  Future<void> prefetch(String text, {required String locale}) async {}
  @override
  Future<VocabularyAudioSource> speakAndWait(
    String text, {
    required String locale,
  }) async {
    spoken.add('$locale:$text');
    await speechGate.future;
    return VocabularyAudioSource.nativeTts;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await stopGate.future;
    if (!speechGate.isCompleted) speechGate.complete();
  }

  @override
  void dispose() {}
}

class _SteppedVocabularyAudioService implements VocabularyContentAudioService {
  final List<String> spoken = <String>[];
  final Queue<Completer<void>> _speechGates = Queue<Completer<void>>();

  void completeCurrentSpeech() {
    final gate = _speechGates.removeFirst();
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<void> prefetch(String text, {required String locale}) async {}

  @override
  Future<VocabularyAudioSource> speakAndWait(
    String text, {
    required String locale,
  }) async {
    spoken.add('$locale:$text');
    final gate = Completer<void>();
    _speechGates.add(gate);
    await gate.future;
    return VocabularyAudioSource.nativeTts;
  }

  @override
  Future<void> stop() async {
    while (_speechGates.isNotEmpty) {
      completeCurrentSpeech();
    }
  }

  @override
  void dispose() {
    unawaited(stop());
  }
}

class _RecordingVoicePromptService implements VoicePromptService {
  final List<String> spokenTexts = <String>[];
  final List<String> locales = <String>[];

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spokenTexts.add(text);
    locales.add(locale);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FailingJourneyVoicePromptService extends _RecordingVoicePromptService {
  bool fail = false;
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    if (fail) {
      throw PlatformException(
        code: 'HFP_ROUTE_LOST',
        message: 'Kết nối âm thanh H20 bị gián đoạn. Hãy thử lại.',
      );
    }
    await super.speakAndWait(text, locale: locale);
  }
}

class _ImmediateLessonMediaService extends LessonMediaService {
  final played = <({Uri uri, double gainDb})>[];

  @override
  Future<void> prepareSelectedLessonOutput() async {}

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = 8.0,
    bool fixedPlaybackGain = false,
  }) async {
    played.add((uri: uri, gainDb: playbackGainDb));
  }

  @override
  Future<void> stopPlayback() async {}
}

class _TransactionalLessonMediaService extends LessonMediaService {
  _TransactionalLessonMediaService({
    int prepareFailures = 0,
    int playFailures = 0,
    Queue<Completer<void>>? playGates,
    this.stopGate,
  }) : _prepareFailures = prepareFailures,
       _playFailures = playFailures,
       _playGates = playGates ?? Queue<Completer<void>>();

  int _prepareFailures;
  int _playFailures;
  final Queue<Completer<void>> _playGates;
  final Completer<void>? stopGate;
  Completer<void>? _activePlayGate;
  int prepareCalls = 0;
  int playCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> prepareSelectedLessonOutput() async {
    prepareCalls++;
    if (_prepareFailures > 0) {
      _prepareFailures--;
      throw PlatformException(
        code: 'HFP_ROUTE_LOST',
        message: 'H20 route unavailable',
      );
    }
  }

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = 8.0,
    bool fixedPlaybackGain = false,
  }) async {
    playCalls++;
    if (_playGates.isNotEmpty) {
      final gate = _playGates.removeFirst();
      _activePlayGate = gate;
      await gate.future;
      if (identical(_activePlayGate, gate)) _activePlayGate = null;
    }
    if (_playFailures > 0) {
      _playFailures--;
      throw PlatformException(
        code: 'PLAYER_START_FAILED',
        message: 'Could not start child recording',
      );
    }
  }

  @override
  Future<void> stopPlayback() async {
    stopCalls++;
    await stopGate?.future;
    final active = _activePlayGate;
    if (active != null && !active.isCompleted) active.complete();
  }
}
