import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_gain.dart';
import 'dart:convert';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/application/vocabulary_audio_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/application/vocabulary_fixed_prompt_audio_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_session_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_dictionary.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_flow_v3.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_practice_screen.dart';
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
    'MAIN generic Vocabulary returns from Stars to the menu',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final prompts = _RecordingVoicePromptService();
      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: DisplayLanguageScope(
              language: DisplayLanguage.vietnamese,
              child: VocabularyHomeScreen(
                isReady: true,
                isActive: true,
                store: _MemoryVocabularyStore(),
                mediaService: _ImmediateLessonMediaService(),
                voicePromptService: prompts,
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
      expect(
        (await registry.execute(
          ActiveLearningCommand.vocabularyStars,
        )).wasHandled,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(find.text('Ngôi sao của bạn'), findsOneWidget);

      expect(await registry.pauseForMainAssistant(), isTrue);
      expect(
        (await registry.execute(
          ActiveLearningCommand.vocabularyRoot,
        )).wasHandled,
        isTrue,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('vocabulary-journey-landing')),
        findsOneWidget,
      );
      expect(prompts.spokenTexts.last, VocabularyFlowV3.menu);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'MAIN generic Vocabulary opens unfinished Today',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final store = _MemoryVocabularyStore(<VocabularyEntry>[
        VocabularyEntry(
          id: 'today-word',
          word: 'Apple',
          meaning: 'Táo',
          addedAt: DateTime(2026, 9, 29),
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
                isActive: true,
                autoStartToday: false,
                store: store,
                mediaService: _ImmediateLessonMediaService(),
                voicePromptService: const _FakeVoicePromptService(),
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

      expect(await registry.pauseForMainAssistant(), isTrue);
      expect(
        (await registry.execute(
          ActiveLearningCommand.vocabularyRoot,
        )).wasHandled,
        isTrue,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(VocabularyPracticeScreen), findsOneWidget);
      expect(
        (await const VocabularySessionStore().readActive())?.mode,
        VocabularyPracticeMode.today,
      );
      expect(await registry.pauseForMainAssistant(), isTrue);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

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
    await tester.pumpAndSettle();

    final childReplays = media.played.where(
      (clip) => clip.uri.path.toLowerCase().endsWith('.wav'),
    );
    expect(childReplays, isNotEmpty);
    expect(
      childReplays.map((clip) => clip.gainDb),
      everyElement(lessonRecordingPlaybackGainDb),
    );
    expect(childReplays.map((clip) => clip.fixed), everyElement(isTrue));
    expect(
      voice.spokenTexts.where((text) => text == VocabularyFlowV3.starMyVoice),
      hasLength(1),
    );
    final next = await registry.execute(ActiveLearningCommand.nextItem);
    expect(next.wasHandled, isTrue);
    await tester.pumpAndSettle();
    expect(
      voice.spokenTexts.where((text) => text == VocabularyFlowV3.starMyVoice),
      hasLength(2),
    );
  });

  testWidgets(
    'missing Star recording stops before speech and keeps checkpoint',
    (tester) async {
      final voice = _RecordingVoicePromptService();
      final media = _MissingRecordingMediaService();
      final store = _MemoryVocabularyStore(<VocabularyEntry>[
        VocabularyEntry(
          id: 'missing-star',
          word: 'English',
          meaning: 'Tiếng Anh',
          addedAt: DateTime(2026, 9, 15),
          collection: VocabularyCollection.star,
          source: VocabularySource.topicCore,
          correctAudioPath: '/missing/star.wav',
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
              mediaService: media,
              voicePromptService: voice,
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
      await tester.tap(find.byKey(const Key('vocabulary-stars-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vocabulary-stars-action')));
      await tester.pumpAndSettle();

      expect(voice.spokenTexts, isNot(contains('English')));
      expect(voice.spokenTexts, isNot(contains('Tiếng Anh')));
      expect(media.played, isEmpty);
      expect(find.textContaining('không còn trên thiết bị'), findsOneWidget);
      expect(
        await const VocabularySessionStore().readPlaybackCheckpoint(
          'stars:ordered',
        ),
        0,
      );
    },
  );

  testWidgets('existing Star recording is retained before it plays', (
    tester,
  ) async {
    final media = _RetainingRecordingMediaService();
    final earnedAt = DateTime(2026, 9, 15);
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      VocabularyEntry(
        id: 'existing-star',
        word: 'English',
        meaning: 'Tiếng Anh',
        addedAt: earnedAt,
        earnedAt: earnedAt,
        collection: VocabularyCollection.star,
        source: VocabularySource.topicCore,
        correctAudioPath: '/recordings/old.wav',
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
            mediaService: media,
            voicePromptService: const _FakeVoicePromptService(),
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
    await tester.tap(find.byKey(const Key('vocabulary-stars-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-stars-action')));
    await tester.pumpAndSettle();

    expect(store.entries.single.correctAudioPath, '/recordings/old.star.wav');
    expect(store.entries.single.earnedAt, earnedAt);
    expect(media.played.single.uri.path, '/recordings/old.star.wav');
  });

  testWidgets('Parent Added follows the active entry below a small viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = _HoldFifthVocabularyAudioService();
    addTearDown(audio.release);
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      for (var index = 0; index < 5; index++)
        VocabularyEntry(
          id: 'word-$index',
          word: 'Word $index',
          meaning: 'Từ $index',
          addedAt: DateTime(2026, 9, 15).add(Duration(minutes: index)),
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
            mediaService: _ImmediateLessonMediaService(),
            voicePromptService: const _FakeVoicePromptService(),
            fixedPromptAudioService:
                const _UnavailableFixedPromptAudioService(),
            vocabularyAudioService: audio,
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
    final action = find.byKey(const Key('vocabulary-family-action'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(audio.spoken, contains('en-US:Word 4'));
    final active = find.byKey(
      const ValueKey<String>('vocabulary-order-word-4'),
    );
    expect(tester.getBottomLeft(active).dy, lessThan(520));
    expect(tester.getTopLeft(active).dy, greaterThan(0));
    audio.release();
    await tester.pumpAndSettle();
  });

  testWidgets('manual drag defers follow until the next spoken entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final audio = _HoldFifthVocabularyAudioService(holdFirst: true);
    addTearDown(audio.release);
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      for (var index = 0; index < 5; index++)
        VocabularyEntry(
          id: 'drag-word-$index',
          word: 'Word $index',
          meaning: 'Từ $index',
          addedAt: DateTime(2026, 9, 15).add(Duration(minutes: index)),
          source: VocabularySource.parent,
          status: VocabularyLearningStatus.learnedWell,
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
              isActive: true,
              store: store,
              mediaService: _ImmediateLessonMediaService(),
              voicePromptService: const _FakeVoicePromptService(),
              fixedPromptAudioService:
                  const _UnavailableFixedPromptAudioService(),
              vocabularyAudioService: audio,
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
    final drag = await tester.startGesture(const Offset(190, 340));
    await drag.moveBy(const Offset(0, -45));
    await tester.pump();
    final first = find.byKey(
      const ValueKey<String>('vocabulary-order-drag-word-0'),
    );
    final duringDrag = tester.getTopLeft(first).dy;
    expect(
      (await registry.execute(
        ActiveLearningCommand.vocabularyParentAdded,
      )).wasHandled,
      isTrue,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(audio.spoken, contains('en-US:Word 0'));
    expect(tester.getTopLeft(first).dy, closeTo(duringDrag, 1));

    await drag.up();
    audio.releaseFirst();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    final fifth = find.byKey(
      const ValueKey<String>('vocabulary-order-drag-word-4'),
    );
    expect(audio.spoken, contains('en-US:Word 4'));
    expect(tester.getBottomLeft(fifth).dy, lessThan(520));
    audio.release();
    await tester.pumpAndSettle();
  });

  testWidgets('active entry above viewport scrolls back into view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final audio = _HoldFifthVocabularyAudioService(holdFirst: true);
    addTearDown(audio.release);
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      for (var index = 0; index < 10; index++)
        VocabularyEntry(
          id: 'up-word-$index',
          word: 'Word $index',
          meaning: 'Từ $index',
          addedAt: DateTime(2026, 9, 15).add(Duration(minutes: index)),
          source: VocabularySource.parent,
          status: VocabularyLearningStatus.learnedWell,
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
              isActive: true,
              store: store,
              mediaService: _ImmediateLessonMediaService(),
              voicePromptService: const _FakeVoicePromptService(),
              fixedPromptAudioService:
                  const _UnavailableFixedPromptAudioService(),
              vocabularyAudioService: audio,
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
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -650),
    );
    await tester.pumpAndSettle();
    final first = find.byKey(
      const ValueKey<String>('vocabulary-order-up-word-0'),
    );
    expect(tester.getBottomLeft(first).dy, lessThan(0));
    expect(
      (await registry.execute(
        ActiveLearningCommand.vocabularyParentAdded,
      )).wasHandled,
      isTrue,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(audio.spoken, contains('en-US:Word 0'));
    expect(tester.getTopLeft(first).dy, greaterThan(0));
    audio.release();
    await tester.pumpAndSettle();
  });

  testWidgets('MAIN resume starts a fresh turn when old speech is stuck', (
    tester,
  ) async {
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final audio = _StuckFirstVocabularyAudioService();
    addTearDown(audio.release);
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      VocabularyEntry(
        id: 'resume-word',
        word: 'Resume word',
        meaning: 'Từ tiếp tục',
        addedAt: DateTime(2026, 9, 15),
        source: VocabularySource.parent,
        status: VocabularyLearningStatus.learnedWell,
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
              isActive: true,
              store: store,
              mediaService: _ImmediateLessonMediaService(),
              voicePromptService: const _FakeVoicePromptService(),
              fixedPromptAudioService:
                  const _UnavailableFixedPromptAudioService(),
              vocabularyAudioService: audio,
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
    await tester.tap(find.byKey(const Key('vocabulary-family-action')));
    await tester.pump();
    expect(
      audio.spoken.where((text) => text == 'en-US:Resume word'),
      hasLength(1),
    );

    expect(await registry.pauseForMainAssistant(), isTrue);
    expect(
      (await registry.execute(ActiveLearningCommand.resume)).wasHandled,
      isTrue,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      audio.spoken.where((text) => text == 'en-US:Resume word'),
      hasLength(2),
    );
    audio.release();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'MAIN resume restarts a collection interrupted during its intro',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final prompt = _InterruptibleVoicePromptService();
      addTearDown(prompt.complete);
      final audio = _RecordingVocabularyAudioService();
      final store = _MemoryVocabularyStore(<VocabularyEntry>[
        VocabularyEntry(
          id: 'intro-word',
          word: 'Intro word',
          meaning: 'Từ mở đầu',
          addedAt: DateTime(2026, 9, 15),
          source: VocabularySource.parent,
          status: VocabularyLearningStatus.learnedWell,
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
                isActive: true,
                store: store,
                mediaService: _ImmediateLessonMediaService(),
                voicePromptService: prompt,
                fixedPromptAudioService:
                    const _UnavailableFixedPromptAudioService(),
                vocabularyAudioService: audio,
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
          ActiveLearningCommand.vocabularyParentAdded,
        )).wasHandled,
        isTrue,
      );
      await tester.pump();
      expect(prompt.started, isTrue);
      expect(audio.spoken, isEmpty);

      expect(await registry.pauseForMainAssistant(), isTrue);
      expect(
        (await registry.execute(ActiveLearningCommand.resume)).wasHandled,
        isTrue,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.spoken, contains('en-US:Intro word'));
    },
  );

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
    'prepared MAIN Stars skips Today menu and preserves unfinished Review',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final activationController = VocabularyActivationController();
      final navigationController = VocabularyHomeNavigationController();
      addTearDown(registry.dispose);
      addTearDown(activationController.dispose);
      final store = _MemoryVocabularyStore(<VocabularyEntry>[
        VocabularyEntry(
          id: 'review-word',
          word: 'Apple',
          meaning: 'Táo',
          addedAt: DateTime(2026, 9, 29),
          collection: VocabularyCollection.review,
          status: VocabularyLearningStatus.needsPractice,
          source: VocabularySource.topicCore,
        ),
      ]);
      const sessions = VocabularySessionStore();
      final review = await sessions.prepareReview(store);
      expect(review, isNotNull);
      await sessions.saveActive(review!);
      final prompts = _RecordingVoicePromptService();
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
                autoStartToday: true,
                activationController: activationController,
                navigationController: navigationController,
                store: store,
                sessionStore: sessions,
                mediaService: _ImmediateLessonMediaService(),
                voicePromptService: prompts,
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

      navigationController.prepareVoiceTarget(VoiceVocabularyTarget.star);
      activationController.activate();
      await tester.pump();
      await navigationController.openVoiceTarget(VoiceVocabularyTarget.star);
      await tester.pumpAndSettle();

      expect(find.byType(VocabularyPracticeScreen), findsNothing);
      expect(find.text('Ngôi sao của bạn'), findsOneWidget);
      expect(prompts.spokenTexts, contains(VocabularyFlowV3.starEmpty));
      expect(prompts.spokenTexts, isNot(contains(VocabularyFlowV3.menu)));
      expect((await sessions.readActive())?.id, review.id);
      expect(navigationController.preparedVoiceTarget, isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  for (final (command, title) in <(ActiveLearningCommand, String)>[
    (ActiveLearningCommand.vocabularyStars, 'Ngôi sao của bạn'),
    (ActiveLearningCommand.vocabularyParentAdded, 'Ba mẹ đã thêm'),
  ]) {
    testWidgets(
      'MAIN opens $title from Vocabulary root despite unfinished Review',
      (tester) async {
        final registry = ActiveLearningModuleRegistry();
        addTearDown(registry.dispose);
        final store = _MemoryVocabularyStore(<VocabularyEntry>[
          VocabularyEntry(
            id: 'review-word',
            word: 'Apple',
            meaning: 'Táo',
            addedAt: DateTime(2026, 9, 29),
            collection: VocabularyCollection.review,
            status: VocabularyLearningStatus.needsPractice,
            source: VocabularySource.topicCore,
          ),
        ]);
        const sessions = VocabularySessionStore();
        final review = await sessions.prepareReview(store);
        expect(review, isNotNull);
        await sessions.saveActive(review!);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: ActiveLearningModuleScope(
              registry: registry,
              child: DisplayLanguageScope(
                language: DisplayLanguage.vietnamese,
                child: VocabularyHomeScreen(
                  isReady: true,
                  store: store,
                  sessionStore: sessions,
                  mediaService: _ImmediateLessonMediaService(),
                  voicePromptService: _RecordingVoicePromptService(),
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

        expect((await registry.execute(command)).wasHandled, isTrue);
        await tester.pumpAndSettle();

        expect(find.byType(VocabularyPracticeScreen), findsNothing);
        expect(find.text(title), findsOneWidget);
        expect((await sessions.readActive())?.id, review.id);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets(
    'a Review checkpoint does not replace a requested Stars journey',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final voice = _RecordingVoicePromptService();
      final navigation = VocabularyHomeNavigationController();
      final store = _MemoryVocabularyStore(_starAndReviewEntries());
      final checkpoint = await const VocabularySessionStore().prepareReview(
        store,
      );
      expect(checkpoint?.mode, VocabularyPracticeMode.review);

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
                mediaService: _ImmediateLessonMediaService(),
                voicePromptService: voice,
                fixedPromptAudioService:
                    const _UnavailableFixedPromptAudioService(),
                navigationController: navigation,
                onReturnToConversation: () {},
                onHistory: () {},
                onSettings: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      unawaited(navigation.openVoiceTarget(VoiceVocabularyTarget.star));
      await tester.pumpAndSettle();

      expect(find.byType(VocabularyPracticeScreen), findsNothing);
      expect(find.text('Ngôi sao của bạn'), findsOneWidget);
      expect(voice.spokenTexts, contains(VocabularyFlowV3.starIntro));
      expect(
        (await const VocabularySessionStore().readActive())?.id,
        checkpoint?.id,
      );
    },
  );

  testWidgets(
    'a voice target owns the vocabulary entry instead of the automatic menu',
    (tester) async {
      final registry = ActiveLearningModuleRegistry();
      final activationController = VocabularyActivationController();
      addTearDown(registry.dispose);
      addTearDown(activationController.dispose);
      final voice = _RecordingVoicePromptService();
      final navigation = VocabularyHomeNavigationController();
      final choicePrompts = <String?>[];
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
                autoStartToday: true,
                activationController: activationController,
                store: _MemoryVocabularyStore(_starAndReviewEntries()),
                mediaService: _ImmediateLessonMediaService(),
                voicePromptService: voice,
                fixedPromptAudioService:
                    const _UnavailableFixedPromptAudioService(),
                navigationController: navigation,
                onRequestVoiceChoice:
                    ({
                      String? noSpeechRetryPrompt,
                      String? noSpeechExitPrompt,
                    }) async {
                      choicePrompts.add(noSpeechRetryPrompt);
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

      // MAIN activates the tab, then opens the section the child asked for.
      activationController.activate(autoStart: false);
      unawaited(navigation.openVoiceTarget(VoiceVocabularyTarget.star));
      await tester.pumpAndSettle();

      expect(find.byType(VocabularyPracticeScreen), findsNothing);
      expect(find.text('Ngôi sao của bạn'), findsOneWidget);
      expect(voice.spokenTexts, isNot(contains(VocabularyFlowV3.menu)));
      expect(choicePrompts, <String?>[VocabularyFlowV3.starFinished]);
    },
  );
}

List<VocabularyEntry> _starAndReviewEntries() {
  final day = DateTime(2026, 9, 15);
  return <VocabularyEntry>[
    VocabularyEntry(
      id: 'star-1',
      word: 'Good morning',
      meaning: 'Chào buổi sáng',
      addedAt: day,
      earnedAt: day,
      collection: VocabularyCollection.star,
      source: VocabularySource.topicCore,
      correctAudioPath: '/audio/star-1.wav',
    ),
    VocabularyEntry(
      id: 'review-1',
      word: 'Banana',
      meaning: 'Chuối',
      addedAt: day,
      status: VocabularyLearningStatus.needsPractice,
      source: VocabularySource.topicCore,
    ),
  ];
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
  final List<String> spoken = <String>[];

  @override
  Future<void> prefetch(String text, {required String locale}) async {
    prefetched.add('$locale:$text');
  }

  @override
  Future<VocabularyAudioSource> speakAndWait(
    String text, {
    required String locale,
  }) async {
    spoken.add('$locale:$text');
    return VocabularyAudioSource.nativeTts;
  }

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
  final played = <({Uri uri, double gainDb, bool fixed})>[];

  @override
  Future<String?> availableRecordingPath(String path) async => path;

  @override
  Future<String?> preserveStarRecording(String path) async => null;

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
    played.add((uri: uri, gainDb: playbackGainDb, fixed: fixedPlaybackGain));
  }

  @override
  Future<void> stopPlayback() async {}
}

class _MissingRecordingMediaService extends _ImmediateLessonMediaService {
  @override
  Future<String?> availableRecordingPath(String path) async => null;
}

class _RetainingRecordingMediaService extends _ImmediateLessonMediaService {
  @override
  Future<String?> preserveStarRecording(String path) async =>
      path.replaceFirst('.wav', '.star.wav');
}

class _HoldFifthVocabularyAudioService
    implements VocabularyContentAudioService {
  _HoldFifthVocabularyAudioService({this.holdFirst = false});

  final bool holdFirst;
  final spoken = <String>[];
  final Completer<void> _first = Completer<void>();
  final Completer<void> _fifth = Completer<void>();

  void releaseFirst() {
    if (!_first.isCompleted) _first.complete();
  }

  void release() {
    releaseFirst();
    if (!_fifth.isCompleted) _fifth.complete();
  }

  @override
  Future<void> prefetch(String text, {required String locale}) async {}

  @override
  Future<VocabularyAudioSource> speakAndWait(
    String text, {
    required String locale,
  }) async {
    spoken.add('$locale:$text');
    if (holdFirst && locale == 'en-US' && text == 'Word 0') {
      await _first.future;
    }
    if (locale == 'en-US' && text == 'Word 4') await _fifth.future;
    return VocabularyAudioSource.nativeTts;
  }

  @override
  Future<void> stop() async => release();

  @override
  void dispose() => release();
}

class _StuckFirstVocabularyAudioService
    implements VocabularyContentAudioService {
  final spoken = <String>[];
  final Completer<void> _first = Completer<void>();

  void release() {
    if (!_first.isCompleted) _first.complete();
  }

  @override
  Future<void> prefetch(String text, {required String locale}) async {}

  @override
  Future<VocabularyAudioSource> speakAndWait(
    String text, {
    required String locale,
  }) async {
    spoken.add('$locale:$text');
    if (spoken.length == 1) await _first.future;
    return VocabularyAudioSource.nativeTts;
  }

  @override
  Future<void> stop() async {}

  @override
  void dispose() => release();
}
