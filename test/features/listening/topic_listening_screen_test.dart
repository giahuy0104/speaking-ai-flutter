import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_lesson_list_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/listening_route_names.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildSubject({
    int childAge = 6,
    DisplayLanguage language = DisplayLanguage.vietnamese,
    double textScale = 1,
    ThemeMode themeMode = ThemeMode.light,
    Future<void> Function()? onVoiceNavigationPause,
    VoidCallback? onVoiceNavigationResume,
    Future<ListeningContentCatalog>? contentFuture,
    ListeningProgressStore? progressStore,
    TopicLessonSelectionPrompt? onLessonSelectionRequested,
    TopicSelectionPrompt? onTopicSelectionRequested,
    ValueListenable<int>? iosTopicRecognitionFailureRevision,
    CourseRelearnTopicSelectionPrompt? onCourseRelearnTopicSelectionRequested,
    ValueChanged<int>? onChildAgeChanged,
    Future<bool> Function()? onRequestParentAccess,
    Future<void> Function()? onMainPressed,
    VoidCallback? onVocabularyRequested,
    LessonMediaService? mediaService,
    VoicePromptService? voicePromptService,
  }) {
    return MaterialApp(
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: themeMode,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
        ),
        child: TopicListeningScreen(
          language: language,
          childAge: childAge,
          onVoiceNavigationPause: onVoiceNavigationPause,
          onVoiceNavigationResume: onVoiceNavigationResume,
          contentFuture: contentFuture,
          progressStore: progressStore ?? _MemoryProgressStore(),
          onLessonSelectionRequested: onLessonSelectionRequested,
          onTopicSelectionRequested: onTopicSelectionRequested,
          iosTopicRecognitionFailureRevision:
              iosTopicRecognitionFailureRevision,
          onCourseRelearnTopicSelectionRequested:
              onCourseRelearnTopicSelectionRequested,
          onChildAgeChanged: onChildAgeChanged,
          onRequestParentAccess: onRequestParentAccess,
          onMainPressed: onMainPressed,
          onVocabularyRequested: onVocabularyRequested,
          mediaService: mediaService,
          voicePromptService:
              voicePromptService ?? _ImmediateVoicePromptService(),
        ),
      ),
    );
  }

  testWidgets('all ten topics can be selected by touch in every age group', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final content = await AssetListeningContentRepository().load();
    for (final group in content.groups) {
      await tester.pumpWidget(
        buildSubject(
          childAge: group.startAge,
          contentFuture: Future.value(content),
          onTopicSelectionRequested:
              ({
                required childAge,
                required topicNumbers,
                required completedTopicNumbers,
              }) async => true,
        ),
      );
      await tester.pumpAndSettle();
      for (final topic in group.topics) {
        final action = find.byKey(
          ValueKey(
            'topic-action-${group.startAge}-${group.endAge}-${topic.number - 1}',
          ),
        );
        await tester.scrollUntilVisible(
          action,
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('topic-listening-screen')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(tester.element(action), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final listFinder = find.byType(
          TopicLessonListScreen,
          skipOffstage: false,
        );
        expect(
          listFinder,
          findsOneWidget,
          reason: '${group.startAge}/${topic.number}',
        );
        final list = tester.widget<TopicLessonListScreen>(listFinder);
        expect(list.content.id, topic.id);
        expect(list.initialLessonNumber, topic.lessons.first.number);
        expect(find.textContaining('Bạn cần hoàn thành Level'), findsNothing);
        Navigator.of(
          tester.element(listFinder),
        ).popUntil((route) => route.isFirst);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('dark theme keeps the listening journey text readable', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final journeyTitle = tester.widget<Text>(find.text('Hành trình của bạn'));
    final groupLabel = tester.widget<Text>(find.text('Nhóm bài học hiện tại'));
    final theme = Theme.of(
      tester.element(find.byKey(const Key('topic-listening-screen'))),
    );

    expect(theme.brightness, Brightness.dark);
    expect(journeyTitle.style?.color, theme.colorScheme.onSurface);
    expect(groupLabel.style?.color, theme.colorScheme.primary);
  });

  testWidgets('topic navigation exposes the shared MAIN action', (
    tester,
  ) async {
    var mainPresses = 0;
    await tester.pumpWidget(
      buildSubject(onMainPressed: () async => mainPresses += 1),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('listening-main-button')));
    await tester.pump();

    expect(mainPresses, 1);
    expect(find.byKey(const Key('listening-topics-tab')), findsOneWidget);
    expect(find.byKey(const Key('listening-vocabulary-tab')), findsOneWidget);
  });

  testWidgets('topic prompts prepare and use the selected H20 output', (
    tester,
  ) async {
    final media = _SelectedOutputMediaService();
    final prompt = _SelectedOutputVoicePromptService();

    await tester.pumpWidget(
      buildSubject(mediaService: media, voicePromptService: prompt),
    );
    await tester.pumpAndSettle();

    expect(media.prepareSelectedOutputCalls, greaterThan(0));
    expect(prompt.selectedOutputPrompts, isNotEmpty);
    expect(prompt.defaultOutputPrompts, isEmpty);
  });

  testWidgets(
    'each age group restores all ten topics without resetting progress',
    (tester) async {
      for (final childAge in [3, 6, 8, 11, 13]) {
        final store = _MemoryProgressStore()
          ..checkpoint = const ListeningTopicSelectionCheckpoint();
        await store.saveLesson('retained-lesson', 3);
        final prompts = <List<int>>[];
        await tester.pumpWidget(
          buildSubject(
            childAge: childAge,
            progressStore: store,
            onTopicSelectionRequested:
                ({
                  required childAge,
                  required topicNumbers,
                  required completedTopicNumbers,
                }) async {
                  prompts.add(topicNumbers);
                  return true;
                },
          ),
        );
        await tester.pumpAndSettle();
        expect(prompts.single, List.generate(10, (index) => index + 1));
        expect(store.checkpoint, isNotNull);
        expect(await store.readLesson('retained-lesson'), 3);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets('completed early topics do not narrow the age-group selection', (
    tester,
  ) async {
    final catalog = await AssetListeningContentRepository().load();
    final group = catalog.groups.first;
    final store = _MemoryProgressStore()
      ..checkpoint = const ListeningTopicSelectionCheckpoint();
    for (final topic in group.topics.take(3)) {
      for (final lesson in topic.lessons) {
        await store.saveLesson(lesson.id, lesson.sentences.length);
        await store.markV4LessonActivityCompleted(lesson.id);
      }
    }
    List<int>? offered;
    List<int>? completed;
    await tester.pumpWidget(
      buildSubject(
        childAge: 3,
        contentFuture: Future.value(catalog),
        progressStore: store,
        onTopicSelectionRequested:
            ({
              required childAge,
              required topicNumbers,
              required completedTopicNumbers,
            }) async {
              offered = topicNumbers;
              completed = completedTopicNumbers;
              return true;
            },
      ),
    );
    await tester.pumpAndSettle();
    expect(offered, List.generate(10, (index) => index + 1));
    expect(completed, [1, 2, 3]);
  });

  for (final throwsActivation in [false, true]) {
    testWidgets(
      'failed topic assistant offers a working Topic 2 choice (throws=$throwsActivation)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final voice = _GatedTopicIntroVoicePromptService();
        final media = _SelectedOutputMediaService();
        await tester.pumpWidget(
          buildSubject(
            childAge: 3,
            voicePromptService: voice,
            mediaService: media,
            onTopicSelectionRequested:
                ({
                  required childAge,
                  required topicNumbers,
                  required completedTopicNumbers,
                }) async {
                  if (throwsActivation) {
                    throw StateError('microphone unavailable');
                  }
                  return false;
                },
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('topic-choice-2')), findsOneWidget);
        expect(voice.spoken.single, contains('Bạn chọn Chủ đề số mấy?'));

        await tester.tap(find.byKey(const ValueKey('topic-choice-2')));
        for (var index = 0; index < 5; index++) {
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 400));
        final intro = tester.widget<LessonIntroScreen>(
          find.byType(LessonIntroScreen),
        );
        expect(intro.topicContent?.number, 2);
        expect(intro.lesson.number, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets(
    'iOS offers Topic 2 after activated recognition fails later',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final failureRevision = ValueNotifier<int>(0);
      addTearDown(failureRevision.dispose);
      final store = _MemoryProgressStore()
        ..checkpoint = const ListeningTopicSelectionCheckpoint();
      var activations = 0;
      await tester.pumpWidget(
        buildSubject(
          childAge: 3,
          progressStore: store,
          iosTopicRecognitionFailureRevision: failureRevision,
          onTopicSelectionRequested:
              ({
                required childAge,
                required topicNumbers,
                required completedTopicNumbers,
              }) async {
                activations += 1;
                return true;
              },
        ),
      );
      await tester.pumpAndSettle();
      expect(activations, 1);
      expect(find.byKey(const ValueKey('topic-choice-2')), findsNothing);

      failureRevision.value += 1;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-choice-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-choice-3')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-choice-2')));
      for (var index = 0; index < 5; index++) {
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));

      final intro = tester.widget<LessonIntroScreen>(
        find.byType(LessonIntroScreen),
      );
      expect(intro.topicContent?.number, 2);
      expect(intro.lesson.number, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'Android ignores iOS recognition failure signal',
    (tester) async {
      final failureRevision = ValueNotifier<int>(0);
      addTearDown(failureRevision.dispose);
      final store = _MemoryProgressStore()
        ..checkpoint = const ListeningTopicSelectionCheckpoint();
      await tester.pumpWidget(
        buildSubject(
          childAge: 3,
          progressStore: store,
          iosTopicRecognitionFailureRevision: failureRevision,
          onTopicSelectionRequested:
              ({
                required childAge,
                required topicNumbers,
                required completedTopicNumbers,
              }) async => true,
        ),
      );
      await tester.pumpAndSettle();
      failureRevision.value += 1;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-choice-2')), findsNothing);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
    }),
  );

  testWidgets('shows bilingual topic and lesson titles', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject(childAge: 6));
    await tester.pumpAndSettle();

    expect(find.text('Từ vựng theo chữ cái'), findsOneWidget);
    expect(find.text('ABC Words'), findsOneWidget);
    final englishTopicTitle = tester.widget<Text>(find.text('ABC Words'));
    final vietnameseTopicTitle = tester.widget<Text>(
      find.text('Từ vựng theo chữ cái'),
    );
    expect(
      tester.getTopLeft(find.text('ABC Words')).dy,
      lessThan(tester.getTopLeft(find.text('Từ vựng theo chữ cái')).dy),
    );
    expect(
      englishTopicTitle.style?.fontSize,
      greaterThan(vietnameseTopicTitle.style?.fontSize ?? 0),
    );

    await tester.tap(find.byKey(const ValueKey('topic-action-6-7-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('topic-lesson-list-screen')), findsOneWidget);
    expect(find.byKey(const Key('topic-header-english-title')), findsOneWidget);
    expect(find.text('ABC Words'), findsOneWidget);
    expect(find.text('Lesson 1 · K to O Letters'), findsOneWidget);
    expect(find.text('Bài 1 · Các chữ cái từ K đến O'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Lesson 1 · K to O Letters')).dy,
      lessThan(
        tester.getTopLeft(find.text('Bài 1 · Các chữ cái từ K đến O')).dy,
      ),
    );
  });

  test(
    'V4 journey cards match the source catalog and keep their images',
    () async {
      final content = await AssetListeningContentRepository().load();

      expect(listeningCatalogs, hasLength(5));
      expect(
        listeningCatalogs.expand((catalog) => catalog.topics),
        hasLength(50),
      );
      for (final group in content.groups) {
        final journey = listeningCatalogs.singleWhere(
          (catalog) =>
              catalog.startAge == group.startAge &&
              catalog.endAge == group.endAge,
        );
        expect(journey.topics, hasLength(group.topics.length));
        for (var index = 0; index < group.topics.length; index += 1) {
          final journeyTopic = journey.topics[index];
          final contentTopic = group.topics[index];
          expect(journeyTopic.titleVi, contentTopic.titleVi);
          expect(journeyTopic.total, contentTopic.lessons.length);
          expect(
            journeyTopic.imagePath,
            isNotNull,
            reason: journeyTopic.titleVi,
          );
          final bytes = await rootBundle.load(journeyTopic.imagePath!);
          expect(
            bytes.lengthInBytes,
            greaterThan(1000),
            reason: journeyTopic.titleVi,
          );
        }
      }
    },
  );

  testWidgets(
    'parent can change the global V4 age group from the topic screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var parentGateCalls = 0;
      int? selectedAge;
      await tester.pumpWidget(
        buildSubject(
          onRequestParentAccess: () async {
            parentGateCalls += 1;
            return true;
          },
          onChildAgeChanged: (age) => selectedAge = age,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nhóm bài học hiện tại'), findsOneWidget);
      expect(find.text('10 chủ đề'), findsOneWidget);
      expect(find.byKey(const Key('topic-age-selector')), findsOneWidget);

      await tester.tap(find.byKey(const Key('topic-age-selector')));
      await tester.pumpAndSettle();
      expect(parentGateCalls, 1);
      expect(find.text('Chọn nhóm bài học'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('age-8-10')));
      await tester.tap(find.byKey(const Key('apply-topic-age')));
      await tester.pumpAndSettle();

      expect(selectedAge, 8);
      expect(find.text('8–10 tuổi'), findsOneWidget);
      expect(find.text('Lịch sinh hoạt của mình'), findsOneWidget);
    },
  );

  testWidgets(
    'opens the V4 listen-first lesson journey from a selected topic',
    (tester) async {
      var voiceNavigationPauseCount = 0;
      var voiceNavigationResumeCount = 0;
      final lessonPrompts =
          <
            ({int childAge, int topicNumber, List<int> completedLessonNumbers})
          >[];
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        buildSubject(
          childAge: 3,
          onVoiceNavigationPause: () async {
            voiceNavigationPauseCount += 1;
          },
          onVoiceNavigationResume: () {
            voiceNavigationResumeCount += 1;
          },
          onLessonSelectionRequested:
              ({
                required childAge,
                required topicNumber,
                required topicContent,
                required completedLessonNumbers,
              }) async {
                lessonPrompts.add((
                  childAge: childAge,
                  topicNumber: topicNumber,
                  completedLessonNumbers: completedLessonNumbers,
                ));
              },
        ),
      );
      await tester.pumpAndSettle();

      final topic = find.byKey(const ValueKey('topic-action-3-5-0'));
      await tester.scrollUntilVisible(
        topic,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('topic-listening-screen')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(topic);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byType(TopicLessonListScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(voiceNavigationPauseCount, 1);
      expect(voiceNavigationResumeCount, 0);
      expect(lessonPrompts, isEmpty);

      expect(find.byKey(const Key('lesson-overview-screen')), findsNothing);
      expect(find.text('Nghe tổng quan'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reports completed V4 topics again after replaying one', (
    tester,
  ) async {
    final content = await AssetListeningContentRepository().load();
    final progressStore = _MemoryProgressStore();
    final topic = content.topic(startAge: 6, endAge: 7, topicNumber: 1);
    for (final lesson in topic.lessons) {
      await progressStore.saveLesson(lesson.id, lesson.sentences.length);
      await progressStore.markV4LessonActivityCompleted(lesson.id);
    }
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildSubject(
        childAge: 6,
        contentFuture: Future<ListeningContentCatalog>.value(content),
        progressStore: progressStore,
      ),
    );
    await tester.pumpAndSettle();

    final firstTopic = find.byKey(const ValueKey('topic-action-6-7-0'));
    await tester.ensureVisible(firstTopic);
    await tester.tap(firstTopic);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Chủ đề 1 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 1?',
      ),
      findsWidgets,
    );
    await tester.tap(find.text('Học lại').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byType(TopicLessonListScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(await progressStore.readLesson(topic.lessons.first.id), 0);
  });

  testWidgets('an in-progress topic resumes with its authored audio key', (
    tester,
  ) async {
    final content = await AssetListeningContentRepository().load();
    final topic = content.topic(startAge: 6, endAge: 7, topicNumber: 1);
    final progressStore = _MemoryProgressStore()..coreStarted = true;
    await progressStore.saveLesson(topic.lessons.first.id, 1);
    final prompts = _SelectedOutputVoicePromptService();

    await tester.pumpWidget(
      buildSubject(
        childAge: 6,
        contentFuture: Future<ListeningContentCatalog>.value(content),
        progressStore: progressStore,
        mediaService: _SelectedOutputMediaService(),
        voicePromptService: prompts,
      ),
    );
    await tester.pumpAndSettle();
    prompts.selectedOutputKeys.clear();

    final firstTopic = find.byKey(const ValueKey('topic-action-6-7-0'));
    await tester.ensureVisible(firstTopic);
    await tester.tap(firstTopic);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      prompts.selectedOutputKeys,
      contains(ListeningAudioKeys.topicResume(1)),
    );
  });

  testWidgets(
    'an in-progress topic opens its lesson while the resume line plays',
    (tester) async {
      final content = await AssetListeningContentRepository().load();
      final topic = content.topic(startAge: 3, endAge: 5, topicNumber: 1);
      final progressStore = _LessonIntroProgressStore()..coreStarted = true;
      await progressStore.saveLesson(topic.lessons.first.id, 1);
      final prompts = _HeldTopicResumeVoicePromptService();

      await tester.pumpWidget(
        buildSubject(
          childAge: 3,
          contentFuture: Future<ListeningContentCatalog>.value(content),
          progressStore: progressStore,
          mediaService: _SelectedOutputMediaService(),
          voicePromptService: prompts,
        ),
      );
      await tester.pumpAndSettle();
      prompts.selectedOutputKeys.clear();
      prompts.selectedOutputPrompts.clear();

      final firstTopic = find.byKey(const ValueKey('topic-action-3-5-0'));
      await tester.ensureVisible(firstTopic);
      await tester.tap(firstTopic);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byType(LessonIntroScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(prompts.selectedOutputPrompts, <String>[
        'Mình học tiếp Chủ đề 1 nhé.',
      ]);
    },
  );

  testWidgets('the initial lesson intro waits for a lead prompt', (
    tester,
  ) async {
    final content = await AssetListeningContentRepository().load();
    final topicContent = content.topic(startAge: 3, endAge: 5, topicNumber: 1);
    final progressStore = _LessonIntroProgressStore()..coreStarted = true;
    await progressStore.saveLesson(topicContent.lessons.first.id, 1);
    final prompts = _SelectedOutputVoicePromptService();
    final leadPrompt = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: TopicLessonListScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
          topic: listeningCatalogs.first.topics.first,
          content: topicContent,
          progressStore: progressStore,
          mediaService: _SelectedOutputMediaService(),
          voicePromptService: prompts,
          initialLessonNumber: topicContent.lessons.first.number,
          initialLessonLeadPrompt: leadPrompt.future,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LessonIntroScreen, skipOffstage: false), findsOneWidget);
    expect(prompts.selectedOutputPrompts, isEmpty);

    leadPrompt.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(prompts.selectedOutputPrompts, isNotEmpty);
  });

  testWidgets(
    'completed Course asks MAIN to choose one of ten topics for relearn',
    (tester) async {
      final content = await AssetListeningContentRepository().load();
      final progressStore = _MemoryProgressStore()..courseCompleted = true;
      int? requestedAge;
      List<int>? requestedLevels;

      await tester.pumpWidget(
        buildSubject(
          childAge: 6,
          contentFuture: Future<ListeningContentCatalog>.value(content),
          progressStore: progressStore,
          onCourseRelearnTopicSelectionRequested:
              ({required childAge, required topicNumbers}) async {
                requestedAge = childAge;
                requestedLevels = topicNumbers;
                return true;
              },
        ),
      );
      await tester.pumpAndSettle();

      expect(requestedAge, 6);
      expect(requestedLevels, List.generate(10, (index) => index + 1));
    },
  );

  for (final throwsActivation in [false, true]) {
    testWidgets(
      'failed completed Course assistant can replay only Topic 1 (throws=$throwsActivation)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final catalog = await AssetListeningContentRepository().load();
        final group = catalog.groups.firstWhere((group) => group.startAge == 3);
        final store = _MemoryProgressStore()..courseCompleted = true;
        for (final topic in group.topics) {
          for (final lesson in topic.lessons) {
            await store.saveLesson(lesson.id, lesson.sentences.length);
            await store.markV4LessonActivityCompleted(lesson.id);
          }
        }
        await tester.pumpWidget(
          buildSubject(
            childAge: 3,
            progressStore: store,
            contentFuture: Future.value(catalog),
            onCourseRelearnTopicSelectionRequested:
                ({required childAge, required topicNumbers}) async {
                  if (throwsActivation) {
                    throw StateError('microphone unavailable');
                  }
                  return false;
                },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('course-relearn-topic-1')));
        await tester.pumpAndSettle();

        final list = tester.widget<TopicLessonListScreen>(
          find.byType(TopicLessonListScreen, skipOffstage: false),
        );
        expect(list.content.number, 1);
        expect(list.relearnTopicSequence, isTrue);
        expect(list.initialLessonNumber, 1);
        expect(store.checkpoint, isNull);
        expect(
          await store.readLesson(group.topics[1].lessons.first.id),
          group.topics[1].lessons.first.sentences.length,
        );
        final replayTopic = group.topics.first;
        expect(await store.readLesson(replayTopic.lessons.first.id), 0);
        expect(
          await store.hasCompletedV4LessonActivity(
            replayTopic.lessons.first.id,
          ),
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets(
    'does not report a V4 topic complete until its authored activities finish',
    (tester) async {
      final content = await AssetListeningContentRepository().load();
      final progressStore = _MemoryProgressStore();
      final topic = content.topic(startAge: 6, endAge: 7, topicNumber: 1);
      for (final lesson in topic.lessons) {
        await progressStore.saveLesson(lesson.id, lesson.sentences.length);
      }
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        buildSubject(
          childAge: 6,
          contentFuture: Future<ListeningContentCatalog>.value(content),
          progressStore: progressStore,
        ),
      );
      await tester.pumpAndSettle();

      final firstTopic = find.byKey(const ValueKey('topic-action-6-7-0'));
      await tester.ensureVisible(firstTopic);
      await tester.tap(firstTopic);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byType(TopicLessonListScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        await progressStore.hasCompletedV4LessonActivity(
          topic.lessons.first.id,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'renders a V4 song milestone as a normal lesson, not a legacy clip',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildSubject(childAge: 3));
      await tester.pumpAndSettle();

      final topicWithSongMilestone = find.byKey(
        const ValueKey('topic-action-3-5-1'),
      );
      await tester.scrollUntilVisible(
        topicWithSongMilestone,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('topic-listening-screen')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(topicWithSongMilestone);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final lessonList = find.byType(
        TopicLessonListScreen,
        skipOffstage: false,
      );
      expect(lessonList, findsOneWidget);
      Navigator.of(tester.element(lessonList)).popUntil(
        (route) => route.settings.name == ListeningRouteNames.topicLessons,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('topic-lesson-list-screen')), findsOneWidget);
      expect(find.text('Bài hát & chant'), findsNothing);
      expect(find.byKey(const ValueKey('song-c35-l1-t02-b02')), findsNothing);
      final songMilestone = find.byKey(
        const ValueKey('start-lesson-c35-l1-t02-b03'),
      );
      await tester.scrollUntilVisible(songMilestone, 180);
      expect(songMilestone, findsOneWidget);
      expect(find.textContaining('Count With Me'), findsWidgets);
    },
  );

  testWidgets(
    'topic song action appears only with content and opens the existing V4 lesson',
    (tester) async {
      final content = await AssetListeningContentRepository().load();
      final progressStore = _MemoryProgressStore();
      final topic = content.topic(startAge: 3, endAge: 5, topicNumber: 2);
      final songs = topic.availableSongsForAge(3);
      expect(songs, hasLength(1));

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        buildSubject(
          childAge: 3,
          contentFuture: Future<ListeningContentCatalog>.value(content),
          progressStore: progressStore,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('topic-songs-3-5-0')),
        findsNothing,
        reason: 'a topic without songs must not expose an empty action',
      );
      final songAction = find.byKey(const ValueKey('topic-songs-3-5-1'));
      await tester.scrollUntilVisible(
        songAction,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('topic-listening-screen')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(songAction);
      await tester.pumpAndSettle();

      final songListFinder = find.byType(TopicLessonListScreen);
      expect(songListFinder, findsOneWidget);
      final songList = tester.widget<TopicLessonListScreen>(songListFinder);
      expect(songList.songsOnly, isTrue);
      expect(songList.content.id, topic.id);
      expect(
        find.byKey(ValueKey('song-entry-${songs.single.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('lesson-${songs.single.id}')),
        findsNothing,
        reason: 'the V4 lesson must not be rendered a second time',
      );
      expect(await progressStore.readAll(), isEmpty);
      expect(
        await progressStore.readCompletedV4LessonActivities(),
        isEmpty,
        reason: 'opening the song list must not complete any lesson or topic',
      );

      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('topic-listening-screen')), findsOneWidget);
      expect(find.byType(TopicLessonListScreen), findsNothing);
    },
  );

  testWidgets('legacy content.songs opens through the same topic song list', (
    tester,
  ) async {
    final source = await AssetListeningContentRepository().load();
    final sourceGroup = source.groups.singleWhere(
      (group) => group.startAge == 6 && group.endAge == 7,
    );
    final sourceTopic = sourceGroup.topics.first;
    expect(sourceTopic.availableSongsForAge(6), isEmpty);
    final legacy = _legacySong(
      id: 'legacy-topic-song',
      title: 'Hello Song',
      audioId: 'legacy_hello_song',
      sentences: sourceTopic.lessons.first.sentences,
    );
    final topicWithLegacySong = ListeningTopicContent(
      id: sourceTopic.id,
      number: sourceTopic.number,
      titleVi: sourceTopic.titleVi,
      titleEn: sourceTopic.titleEn,
      lessons: sourceTopic.lessons,
      songs: <ListeningLessonContent>[legacy],
      levelNumber: sourceTopic.levelNumber,
    );
    final content = ListeningContentCatalog(
      contentVersion: source.contentVersion,
      groups: source.groups
          .map(
            (group) => identical(group, sourceGroup)
                ? ListeningContentAgeGroup(
                    startAge: group.startAge,
                    endAge: group.endAge,
                    topics: <ListeningTopicContent>[
                      topicWithLegacySong,
                      ...group.topics.skip(1),
                    ],
                    levels: group.levels,
                  )
                : group,
          )
          .toList(growable: false),
    );
    final progressStore = _MemoryProgressStore();

    await tester.pumpWidget(
      buildSubject(
        childAge: 6,
        contentFuture: Future<ListeningContentCatalog>.value(content),
        progressStore: progressStore,
      ),
    );
    await tester.pumpAndSettle();

    final songAction = find.byKey(const ValueKey('topic-songs-6-7-0'));
    expect(songAction, findsOneWidget);
    await tester.tap(songAction);
    await tester.pumpAndSettle();

    final songListFinder = find.byType(TopicLessonListScreen);
    expect(songListFinder, findsOneWidget);
    final songList = tester.widget<TopicLessonListScreen>(songListFinder);
    expect(songList.songsOnly, isTrue);
    expect(songList.songEntries.map((song) => song.id), <String>[
      'legacy-topic-song',
    ]);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('song-entry-legacy-topic-song')),
      findsOneWidget,
    );
    expect(find.textContaining('Hello Song'), findsWidgets);
    expect(await progressStore.readAll(), isEmpty);
  });

  testWidgets('song action is available in later topics without a Level gate', (
    tester,
  ) async {
    final content = await AssetListeningContentRepository().load();
    final lockedTopic = content.topic(startAge: 3, endAge: 5, topicNumber: 9);
    expect(lockedTopic.availableSongsForAge(3), isNotEmpty);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildSubject(
        childAge: 3,
        contentFuture: Future<ListeningContentCatalog>.value(content),
      ),
    );
    await tester.pumpAndSettle();

    final songAction = find.byKey(const ValueKey('topic-songs-3-5-8'));
    await tester.scrollUntilVisible(
      songAction,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('topic-listening-screen')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(songAction),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pump();
    await tester.tap(songAction);
    await tester.pumpAndSettle();

    expect(find.byType(TopicLessonListScreen), findsOneWidget);
    expect(find.textContaining('Level'), findsNothing);
  });

  test(
    'song directory keeps V4 lesson identity and deduplicates legacy audio',
    () async {
      final content = await AssetListeningContentRepository().load();
      final source = content.topic(startAge: 3, endAge: 5, topicNumber: 2);
      final v4Lesson = source.availableSongsForAge(3).single;
      final duplicateLegacy = _legacySong(
        id: 'legacy-duplicate',
        title: v4Lesson.songTitle!,
        audioId: v4Lesson.songAudioId!,
        sentences: v4Lesson.sentences,
      );
      final uniqueLegacy = _legacySong(
        id: 'legacy-unique',
        title: 'A Different Song',
        audioId: 'legacy_unique_song',
        sentences: v4Lesson.sentences,
      );
      final mixed = ListeningTopicContent(
        id: source.id,
        number: source.number,
        titleVi: source.titleVi,
        titleEn: source.titleEn,
        lessons: <ListeningLessonContent>[v4Lesson],
        songs: <ListeningLessonContent>[duplicateLegacy, uniqueLegacy],
      );

      expect(mixed.availableSongsForAge(3), <ListeningLessonContent>[v4Lesson]);
      final olderSongs = mixed.availableSongsForAge(6);
      expect(olderSongs, hasLength(2));
      expect(identical(olderSongs.first, v4Lesson), isTrue);
      expect(identical(olderSongs.last, uniqueLegacy), isTrue);
      expect(
        olderSongs.map((song) => song.id),
        isNot(contains('legacy-duplicate')),
      );
    },
  );

  test(
    'bundled lesson content matches the V4 source-of-truth catalog',
    () async {
      final content = await AssetListeningContentRepository().load();
      final topics = content.groups
          .expand((group) => group.topics)
          .toList(growable: false);
      final lessons = topics
          .expand((topic) => topic.lessons)
          .toList(growable: false);
      final targets = lessons
          .expand((lesson) => lesson.sentences)
          .toList(growable: false);

      expect(content.groups, hasLength(5));
      expect(topics, hasLength(50));
      expect(
        content.groups.every((group) => group.topics.length == 10),
        isTrue,
      );
      expect(lessons, hasLength(109));
      expect(targets, hasLength(565));
      expect(
        lessons.map((lesson) => lesson.id).toSet(),
        hasLength(lessons.length),
      );
      expect(
        targets.map((target) => target.id).toSet(),
        hasLength(targets.length),
      );

      final alphabet = content.topic(startAge: 3, endAge: 5, topicNumber: 1);
      expect(alphabet.titleVi, 'Bảng chữ cái');
      expect(alphabet.levelNumber, 1);
      expect(alphabet.lessons, hasLength(2));
      expect(alphabet.sentenceCount, 10);
      expect(alphabet.lessons.first.id, 'c35-l1-t01-b01');
      expect(alphabet.lessons.first.sentences.first.english, 'A. Apple.');
      expect(
        alphabet.lessons.first.sentences.first.requiresAllExpectedTokens,
        isFalse,
      );

      final classroomTalk = lessons.singleWhere(
        (lesson) => lesson.id == 'c810-l1-t02-b02',
      );
      expect(classroomTalk.titleEn, 'Classroom Talk');
      expect(classroomTalk.rolePlay, isNull);

      final advanced = content.topic(startAge: 13, endAge: 15, topicNumber: 3);
      expect(advanced.titleVi, 'Nêu ý kiến');
      expect(advanced.levelNumber, 1);
      expect(advanced.lessons.first.usesGuidedPractice, isTrue);
    },
  );

  testWidgets(
    'a compact phone can reach the V4 lesson intro without layout errors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildSubject(childAge: 3, textScale: 1.3));
      await tester.pumpAndSettle();

      final compactTopic = find.byKey(const ValueKey('topic-action-3-5-0'));
      await tester.scrollUntilVisible(
        compactTopic,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('topic-listening-screen')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(compactTopic),
        alignment: 0.4,
        duration: Duration.zero,
      );
      await tester.pump();
      await tester.tap(compactTopic);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byType(TopicLessonListScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders the learning journey responsively on web width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-journey-path')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-6-7-0')), findsOneWidget);
    expect(find.text('Hành trình của bạn'), findsOneWidget);
    expect(
      find.byKey(const Key('listening-bottom-navigation')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps core controls available at large text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject(textScale: 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-age-selector')), findsOneWidget);
    expect(find.byKey(const Key('continue-listening-card')), findsNothing);
    expect(
      find.byKey(const Key('listening-bottom-navigation')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

ListeningLessonContent _legacySong({
  required String id,
  required String title,
  required String audioId,
  required List<ListeningSentenceContent> sentences,
}) {
  return ListeningLessonContent(
    id: id,
    number: 1,
    titleVi: title,
    titleEn: title,
    intro: '',
    outro: '',
    estimatedMinutes: 2,
    sentences: sentences,
    type: ListeningLessonType.song,
    fullAudioId: audioId,
  );
}

class _MemoryProgressStore extends ListeningProgressStore {
  bool coreStarted = false;
  bool courseCompleted = false;
  ListeningTopicSelectionCheckpoint? checkpoint;

  @override
  Future<bool> hasStartedLessonCore(String lessonId) async => coreStarted;

  @override
  Future<void> markLessonCoreStarted(String lessonId) async {
    coreStarted = true;
  }

  @override
  Future<bool> hasLessonPendingRelearn(String lessonId) async => false;

  @override
  Future<Set<String>> readStartedLessonCores() async =>
      coreStarted ? <String>{..._progress.keys} : <String>{};

  final Map<String, int> _progress = <String, int>{};
  final Set<String> _completedV4LessonActivities = <String>{};

  @override
  Future<Map<String, int>> readAll() async => Map<String, int>.of(_progress);

  @override
  Future<Set<String>> readCompletedV4LessonActivities() async =>
      Set<String>.of(_completedV4LessonActivities);

  @override
  Future<bool> hasCompletedV4LessonActivity(String lessonId) async =>
      _completedV4LessonActivities.contains(lessonId);

  @override
  Future<void> markV4LessonActivityCompleted(String lessonId) async {
    _completedV4LessonActivities.add(lessonId);
  }

  @override
  Future<bool> isCourseCompleted(String courseId) async => courseCompleted;

  @override
  Future<void> markCourseCompleted(String courseId) async {
    courseCompleted = true;
  }

  @override
  Future<void> resetLevelForRelearn({
    required String levelId,
    required Iterable<String> lessonIds,
  }) async {
    await resetLessonsForRelearn(lessonIds);
  }

  @override
  Future<void> saveLesson(String lessonId, int completedSentences) async {
    final previous = _progress[lessonId] ?? 0;
    if (completedSentences > previous) {
      _progress[lessonId] = completedSentences;
    }
  }

  @override
  Future<int> readLesson(String lessonId) async => _progress[lessonId] ?? 0;

  @override
  Future<bool> hasPassedLevelMission(String levelId) async => false;

  @override
  Future<void> resetLessonsForRelearn(Iterable<String> lessonIds) async {
    for (final lessonId in lessonIds) {
      _progress.remove(lessonId);
      _completedV4LessonActivities.remove(lessonId);
    }
  }

  @override
  Future<void> saveTopicSelectionCheckpoint(String courseId) async {
    checkpoint = ListeningTopicSelectionCheckpoint();
  }

  @override
  Future<ListeningTopicSelectionCheckpoint?> readTopicSelectionCheckpoint(
    String courseId,
  ) async => checkpoint;

  @override
  Future<void> clearTopicSelectionCheckpoint(String courseId) async {
    checkpoint = null;
  }
}

class _ImmediateVoicePromptService implements VoicePromptService {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> stop() async {}
}

class _GatedTopicIntroVoicePromptService extends _ImmediateVoicePromptService {
  final spoken = <String>[];
  final _introGate = Completer<void>();

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    spoken.add(text);
    if (text.contains('Chủ đề 2.')) await _introGate.future;
  }
}

class _SelectedOutputMediaService extends LessonMediaService {
  int prepareSelectedOutputCalls = 0;

  @override
  Future<void> prepareSelectedLessonOutput() async {
    prepareSelectedOutputCalls += 1;
  }

  @override
  Future<void> dispose() async {}
}

class _SelectedOutputVoicePromptService
    implements
        VoicePromptService,
        SelectedMediaOutputVoicePromptService,
        KeyedSelectedMediaOutputVoicePromptService {
  final List<String> selectedOutputPrompts = <String>[];
  final List<String> defaultOutputPrompts = <String>[];
  final List<String> selectedOutputKeys = <String>[];

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    defaultOutputPrompts.add(text);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    defaultOutputPrompts.add(text);
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) async {
    selectedOutputPrompts.add(text);
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutputWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  }) async {
    selectedOutputKeys.add(audioKey);
    selectedOutputPrompts.add(text);
  }

  @override
  Future<void> stop() async {}
}

class _HeldTopicResumeVoicePromptService
    extends _SelectedOutputVoicePromptService {
  final Completer<void> resumeLine = Completer<void>();

  @override
  Future<void> speakAndWaitOnSelectedMediaOutputWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  }) async {
    await super.speakAndWaitOnSelectedMediaOutputWithAudioKey(
      audioKey,
      text,
      locale: locale,
    );
    if (audioKey == ListeningAudioKeys.topicResume(1)) {
      await resumeLine.future;
    }
  }
}

/// Also answers the reads the lesson intro makes before it speaks.
class _LessonIntroProgressStore extends _MemoryProgressStore {
  @override
  Future<int> readCurrentSentence(String lessonId) async => 0;

  @override
  Future<bool> hasOpenedLearningGuide() async => true;

  @override
  Future<ListeningResumeStage> readResumeStage(String lessonId) async =>
      ListeningResumeStage.core;
}
