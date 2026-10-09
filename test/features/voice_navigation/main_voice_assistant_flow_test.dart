import 'dart:async';

import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/v4_completion_flow.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/main_assistant_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MAIN opens every topic 1–10 for all five age groups', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final content = await AssetListeningContentRepository().load();
    for (final group in content.groups) {
      final numbers = group.topics.map((topic) => topic.number).toList();
      for (final number in numbers) {
        final flow = MainVoiceAssistantFlow(contentLoader: () async => content);
        flow.beginTopicSelection(
          childAge: group.startAge,
          topicNumbers: numbers,
          completedTopicNumbers: [],
        );
        final turn = await flow.handle('Chủ đề $number');
        expect(turn.navigationBeforePrompt?.topicNumber, number);
        expect(turn.navigationBeforePrompt?.childAge, group.startAge);
        expect(turn.continueListening, isFalse);
        flow.beginCourseRelearnTopicSelection(
          childAge: group.startAge,
          topicNumbers: numbers,
        );
        final replay = await flow.handle('Học lại Chủ đề $number');
        expect(replay.navigationBeforePrompt?.topicNumber, number);
        expect(replay.navigationBeforePrompt?.relearnTopic, isTrue);
      }
    }
  });

  for (final loaderFails in [false, true]) {
    test(
      'late Topic loading keeps the newer MAIN Level choice (failure=$loaderFails)',
      () async {
        final content = await _loadThreeTopicContent();
        final pendingContent = Completer<ListeningContentCatalog>();
        final flow = MainVoiceAssistantFlow(
          contentLoader: () => pendingContent.future,
          childAge: 6,
        );
        flow.beginTopicSelection(
          childAge: 6,
          topicNumbers: [1, 2, 3],
          completedTopicNumbers: [],
        );
        final previousTurn = flow.handle('Chủ đề 3');
        flow.beginTopicSelection(
          childAge: 6,
          topicNumbers: [2],
          completedTopicNumbers: [],
        );
        final currentPrompt = flow.currentPrompt;
        if (loaderFails) {
          pendingContent.completeError(StateError('old content load failed'));
        } else {
          pendingContent.complete(content);
        }
        final oldTurn = await previousTurn;
        expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);
        expect(flow.currentPrompt, currentPrompt);
        expect(flow.canHandle('Chủ đề 2'), isTrue);
        expect(oldTurn.navigationBeforePrompt, isNull);
        expect(oldTurn.navigationAfterPrompt, isNull);
        expect(oldTurn.promptText, isEmpty);
        final outsideCurrentLevel = await flow.handle('Chủ đề 11');
        expect(outsideCurrentLevel.continueListening, isTrue);
        expect(outsideCurrentLevel.navigationBeforePrompt, isNull);
        expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);
      },
    );
  }

  test(
    'topic command prefixes wait for the final number in every MAIN menu',
    () {
      for (final begin in <void Function(MainVoiceAssistantFlow)>[
        (flow) => flow.begin(),
        (flow) => flow.beginAfterTranslationStop(),
        (flow) => flow.beginOtherLearning(),
        (flow) => flow.beginActiveLearning(
          kind: ActiveLearningModuleKind.listeningLesson,
        ),
      ]) {
        final flow = MainVoiceAssistantFlow(
          contentLoader: _loadThreeTopicContent,
          childAge: 6,
        );
        begin(flow);
        for (final partial in [
          'Chủ đề',
          'Con muốn học chủ đề',
          'Con muốn học chủ đề số',
          'Chủ đề số hai',
        ]) {
          expect(flow.canHandlePartial(partial), isFalse, reason: partial);
        }
        expect(flow.canEndOnSilence('Chủ đề số hai'), isTrue);
        expect(flow.canEndOnSilence('Chủ đề số mười'), isFalse);
      }
    },
  );

  test(
    'module switches keep the direct topic number without another menu',
    () async {
      final topic = (await _loadThreeTopicContent()).topic(
        startAge: 6,
        endAge: 7,
        topicNumber: 3,
      );
      for (final begin in <void Function(MainVoiceAssistantFlow)>[
        (flow) => flow.beginAfterTranslationStop(),
        (flow) => flow.beginOtherLearning(),
        (flow) =>
            flow.beginActiveLearning(kind: ActiveLearningModuleKind.vocabulary),
        (flow) => flow.beginLessonSelectionForTopic(
          childAge: 6,
          topicNumber: 3,
          topicContent: topic,
          completedLessonNumbers: [],
        ),
      ]) {
        final flow = MainVoiceAssistantFlow(
          contentLoader: _loadThreeTopicContent,
          childAge: 6,
        );
        begin(flow);
        expect(flow.canHandle('Topic number two'), isTrue);
        expect(flow.canEndOnSilence('Topic number two'), isTrue);
        final turn = await flow.handle('Topic number two');
        expect(turn.navigationAfterPrompt?.topicNumber, 2);
        expect(turn.navigationAfterPrompt?.childAge, 6);
        expect(turn.promptText, MasterNavigationContract.switchedToSubject);
        expect(turn.continueListening, isFalse);
        expect(flow.stage, MainVoiceAssistantStage.idle);
      }
    },
  );

  test(
    'MAIN keeps a direct numbered topic from Home in its navigation target',
    () async {
      for (final entry in <String, int>{
        'Chủ đề số 1': 1,
        'Chủ đề số hai': 2,
        'Chủ đề số ba': 3,
        'Topic number one': 1,
        'Topic number two': 2,
        'Topic number three': 3,
      }.entries) {
        final flow = MainVoiceAssistantFlow(
          contentLoader: _loadThreeTopicContent,
          childAge: 6,
        );
        flow.begin();
        expect(flow.canHandle(entry.key), isTrue, reason: entry.key);
        expect(flow.canHandlePartial(entry.key), isFalse, reason: entry.key);
        final turn = await flow.handle(entry.key);
        expect(turn.continueListening, isFalse, reason: entry.key);
        expect(
          turn.navigationBeforePrompt?.destination,
          VoiceNavigationDestination.topics,
          reason: entry.key,
        );
        expect(
          turn.navigationBeforePrompt?.topicNumber,
          entry.value,
          reason: entry.key,
        );
        expect(turn.navigationBeforePrompt?.childAge, 6, reason: entry.key);
        expect(turn.navigationBeforePrompt?.relearnTopic, isFalse);
        expect(turn.navigationBeforePrompt?.openLesson, isFalse);
      }
    },
  );

  test(
    'Level selection accepts Vietnamese and English spoken topic numbers',
    () async {
      for (final entry in <String, int>{
        'Chủ đề số một': 1,
        'Chủ đề số hai': 2,
        'Chủ đề số ba': 3,
        'Topic number one': 1,
        'Topic number two': 2,
        'Topic number three': 3,
      }.entries) {
        final flow = MainVoiceAssistantFlow(
          contentLoader: _loadThreeTopicContent,
          childAge: 6,
        );
        flow.beginTopicSelection(
          childAge: 6,
          topicNumbers: const <int>[1, 2, 3],
          completedTopicNumbers: const <int>[],
        );
        expect(flow.canHandle(entry.key), isTrue, reason: entry.key);
        expect(flow.canHandlePartial(entry.key), isFalse, reason: entry.key);
        final turn = await flow.handle(entry.key);
        expect(turn.continueListening, isFalse, reason: entry.key);
        expect(
          turn.navigationBeforePrompt?.topicNumber,
          entry.value,
          reason: entry.key,
        );
      }
    },
  );

  test(
    'numbered direct commands can choose topics outside old Level ranges',
    () async {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        childAge: 6,
      );
      flow.beginTopicSelection(
        childAge: 6,
        topicNumbers: const <int>[1, 2, 3],
        completedTopicNumbers: const <int>[],
      );
      final turn = await flow.handle('Topic number four');
      expect(turn.continueListening, isFalse);
      expect(turn.navigationBeforePrompt?.topicNumber, 4);
      expect(turn.navigationAfterPrompt, isNull);
      expect(flow.stage, MainVoiceAssistantStage.idle);
    },
  );

  test('a complete topic number or bare Topics may end MAIN on silence', () {
    final flow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      childAge: 6,
    );
    expect(flow.canEndOnSilence('Chủ đề số 2'), isFalse);

    flow.beginTopicSelection(
      childAge: 6,
      topicNumbers: const <int>[1, 2, 3],
      completedTopicNumbers: const <int>[],
    );
    expect(flow.canEndOnSilence('Chủ đề số 2'), isTrue);
    expect(flow.canEndOnSilence('số hai'), isTrue);
    expect(flow.canEndOnSilence('Chủ đề'), isTrue);
    expect(flow.canEndOnSilence('Chủ đề số'), isFalse);
    expect(flow.canEndOnSilence('Chủ đề số mười'), isFalse);
    expect(flow.canEndOnSilence('Chủ đề 10'), isFalse);
    expect(flow.canEndOnSilence('Bạn chọn Chủ đề số mấy'), isFalse);
  });

  test('the bare Topics command may end MAIN on silence', () {
    for (final begin in <void Function(MainVoiceAssistantFlow)>[
      (flow) => flow.begin(),
      (flow) => flow.beginAfterTranslationStop(),
      (flow) => flow.beginOtherLearning(),
      (flow) => flow.beginActiveLearning(
        kind: ActiveLearningModuleKind.listeningLesson,
      ),
    ]) {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadThreeTopicContent,
        childAge: 6,
      );
      begin(flow);
      expect(flow.canEndOnSilence('Chủ đề'), isTrue);
      expect(flow.canEndOnSilence('Chủ đề số'), isFalse);
    }
  });

  test('Topic dynamic prompts resolve to authored audio keys', () async {
    final flow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      childAge: 6,
    );

    final levelPrompt = flow.beginTopicSelection(
      childAge: 6,
      topicNumbers: const <int>[1, 2, 3],
      completedTopicNumbers: const <int>[2],
    );
    expect(
      flow.audioKeyForPrompt(levelPrompt),
      MainAssistantAudioKeys.chooseTopic(10),
    );
    expect(flow.silenceRetryAudioKey, MainAssistantAudioKeys.chooseTopic(10));

    final invalid = await flow.handle('Chủ đề số 11');
    expect(
      flow.audioKeyForPrompt(invalid.promptText),
      MainAssistantAudioKeys.invalidTopic(10),
    );

    final replay = await flow.handle('Chủ đề số 2');
    expect(
      flow.audioKeyForPrompt(replay.promptText),
      MainAssistantAudioKeys.replayTopic(2),
    );
    expect(flow.silenceRetryAudioKey, MainAssistantAudioKeys.replayTopic(2));

    final topic = (await _loadContent()).topic(
      startAge: 6,
      endAge: 7,
      topicNumber: 3,
    );
    final lessonPrompt = flow.beginLessonSelectionForTopic(
      childAge: 6,
      topicNumber: 3,
      topicContent: topic,
      completedLessonNumbers: const <int>[],
    );
    expect(
      flow.audioKeyForPrompt(lessonPrompt),
      ListeningAudioKeys.startLessonChoice(1),
    );
    final invalidLesson = await flow.handle('Bài số 9');
    expect(
      flow.audioKeyForPrompt(invalidLesson.promptText),
      ListeningAudioKeys.startLessonChoice(1),
    );
    expect(
      flow.audioKeyForPrompt(
        'Có ${topic.lessons.length} Bài học. '
        'Bạn chọn từ số 1 đến số ${topic.lessons.length}.',
      ),
      ListeningAudioKeys.invalidLessonCount(topic.lessons.length),
    );
  });

  test(
    'global module commands remain available during content selection',
    () async {
      final topic = (await _loadContent()).topic(
        startAge: 6,
        endAge: 7,
        topicNumber: 3,
      );
      final selections = <void Function(MainVoiceAssistantFlow)>[
        (flow) => flow.beginTopicSelection(
          childAge: 6,
          topicNumbers: [1, 2, 3],
          completedTopicNumbers: [],
        ),
        (flow) => flow.beginCourseRelearnTopicSelection(
          childAge: 6,
          topicNumbers: [1, 2, 3],
        ),
        (flow) => flow.beginLessonSelectionForTopic(
          childAge: 6,
          topicNumber: 3,
          topicContent: topic,
          completedLessonNumbers: [],
        ),
        (flow) => flow.beginLessonSelectionForTopic(
          childAge: 6,
          topicNumber: 3,
          topicContent: topic,
          completedLessonNumbers: topic.lessons
              .map((lesson) => lesson.number)
              .toList(),
        ),
      ];
      for (final beginSelection in selections) {
        for (final entry in <String, VoiceNavigationDestination>{
          'OPEN_SUBJECT': VoiceNavigationDestination.topics,
          'OPEN_VOCAB': VoiceNavigationDestination.vocabulary,
          'OPEN_TRANSLATE': VoiceNavigationDestination.conversation,
        }.entries) {
          for (final phrase in MasterNavigationContract.phrases[entry.key]!) {
            final flow = MainVoiceAssistantFlow(
              contentLoader: _loadContent,
              childAge: 6,
            );
            beginSelection(flow);
            final previousStage = flow.stage;
            expect(
              flow.canHandle(phrase),
              isTrue,
              reason: '$previousStage: $phrase',
            );
            expect(
              flow.canHandlePartial(phrase),
              entry.value == VoiceNavigationDestination.topics &&
                      phrase.toLowerCase().endsWith('chủ đề')
                  ? isFalse
                  : isTrue,
              reason: '$previousStage: $phrase',
            );
            final turn = await flow.handle(phrase);
            expect(
              turn.navigationAfterPrompt?.destination,
              entry.value,
              reason: '$previousStage: $phrase',
            );
            expect(turn.continueListening, isFalse);
            expect(flow.stage, MainVoiceAssistantStage.idle);
            if (entry.value == VoiceNavigationDestination.conversation) {
              expect(turn.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
              expect(turn.promptSequence.map((utterance) => utterance.text), [
                MasterNavigationContract.switchedToTranslation,
                MasterNavigationContract.translationIntro,
              ]);
            } else {
              expect(turn.promptSequence, isEmpty);
            }
          }
        }
      }
    },
  );

  test(
    'fast path accepts unambiguous fallback phrases but defers broad input',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.begin();

      expect(flow.canHandlePartial('Con muốn học từ vựng'), isTrue);
      expect(flow.canHandlePartial('Học theo chủ đề'), isFalse);
      expect(flow.canHandlePartial('Mình muốn học'), isFalse);
      expect(flow.canHandlePartial('Dừng lại'), isTrue);

      await flow.handle('Học theo chủ đề');
      expect(flow.stage, MainVoiceAssistantStage.idle);
      expect(flow.canHandlePartial('Con 6 tuổi'), isFalse);
    },
  );

  test(
    'Home accepts an approved feature phrase with lead-in or particle',
    () async {
      for (final entry in <String, VoiceNavigationDestination>{
        'Mở bộ từ vựng': VoiceNavigationDestination.vocabulary,
        'Bộ từ vựng ạ': VoiceNavigationDestination.vocabulary,
        'Ừ bộ từ vựng': VoiceNavigationDestination.vocabulary,
        'Cho con học từ vựng': VoiceNavigationDestination.vocabulary,
        'Con muốn học chủ đề ạ': VoiceNavigationDestination.topics,
        'Dịch sang tiếng Anh nhé': VoiceNavigationDestination.conversation,
      }.entries) {
        final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
        flow.begin();
        final turn = await flow.handle(entry.key);
        expect(
          (turn.navigationBeforePrompt ?? turn.navigationAfterPrompt)
              ?.destination,
          entry.value,
          reason: entry.key,
        );
      }

      // Any other word around the phrase still re-asks: the menu echo, a
      // negation, an embedded destination, or a Topics prefix awaiting a number.
      for (final phrase in <String>[
        'Học chủ đề hay bộ từ vựng',
        'hay bộ từ vựng',
        'Mình không muốn học Chủ đề',
        'Hôm nay mình học từ vựng ở trường',
        'Con muốn học chủ đề số',
      ]) {
        final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
        flow.begin();
        final turn = await flow.handle(phrase);
        expect(turn.navigationBeforePrompt, isNull, reason: phrase);
        expect(turn.navigationAfterPrompt, isNull, reason: phrase);
        expect(turn.continueListening, isTrue, reason: phrase);
      }

      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.begin();
      expect(flow.canHandlePartial('Bộ từ vựng ạ'), isTrue);
      // "Mở chủ đề" may still grow into "Mở chủ đề số hai".
      expect(flow.canHandlePartial('Mở chủ đề'), isFalse);
    },
  );

  test('chooses continuous translation after the Main menu', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    expect(flow.begin(), MainVoiceAssistantFlow.openingPrompt);
    final turn = await flow.handle('Con muốn luyện nói');

    expect(turn.promptText, MainVoiceAssistantFlow.continuousTranslationPrompt);
    expect(turn.continueListening, isFalse);
    expect(
      turn.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(turn.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
  });

  test('accepts short child-friendly continuous speaking choices', () async {
    for (final choice in <String>['Nói', 'Con muốn nói']) {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.begin();

      final turn = await flow.handle(choice);

      expect(
        turn.navigationAfterPrompt?.destination,
        VoiceNavigationDestination.conversation,
        reason: choice,
      );
      expect(turn.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
    }
  });

  test('opens continuous translation directly from the Main choice', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.begin();

    final translation = await flow.handle('Dịch sang tiếng Anh');
    expect(translation.continueListening, isFalse);
    expect(
      translation.promptText,
      MainVoiceAssistantFlow.continuousTranslationPrompt,
    );
    expect(translation.promptSequence, isEmpty);
    expect(translation.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
    expect(flow.stage, MainVoiceAssistantStage.idle);
  });

  test(
    'explicit translation resume keeps its short prompt without extra intro',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.beginAfterTranslationStop();

      final turn = await flow.handle('Tiếp tục dịch');

      expect(turn.promptText, MasterNavigationContract.translationContinue);
      expect(turn.promptSequence, isEmpty);
      expect(turn.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
    },
  );

  test('after translation stop offers topic, vocabulary, or stop', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    expect(
      flow.beginAfterTranslationStop(),
      MainVoiceAssistantFlow.afterTranslationStopPrompt,
    );
    expect(flow.stage, MainVoiceAssistantStage.chooseAfterTranslationStop);
    expect(flow.canHandle('Học chủ đề'), isTrue);
    expect(flow.canHandle('Dừng lại'), isTrue);

    final topic = await flow.handle('Học chủ đề');
    expect(topic.continueListening, isFalse);
    expect(flow.stage, MainVoiceAssistantStage.idle);
  });

  test('offers all three top-level choices from Main', () async {
    final introducedIds = <String>[];
    final vocabularyFlow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      vocabularyLoader: _loadVocabularyAcrossCollections,
      vocabularyIntroducedMarker: (ids) async => introducedIds.addAll(ids),
    );
    expect(vocabularyFlow.begin(), MainVoiceAssistantFlow.openingPrompt);
    final vocabulary = await vocabularyFlow.handle('Học từ mới');
    expect(
      vocabulary.navigationBeforePrompt?.destination,
      VoiceNavigationDestination.vocabulary,
    );
    expect(vocabulary.continueListening, isFalse);
    expect(vocabulary.promptText, isEmpty);
    expect(introducedIds, isEmpty);
    await vocabulary.onPromptCompleted?.call();
    expect(introducedIds, isEmpty);

    final translationFlow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    translationFlow.begin();
    final translation = await translationFlow.handle('Dịch sang tiếng Anh');
    expect(translation.continueListening, isFalse);
    expect(
      translation.promptText,
      MainVoiceAssistantFlow.continuousTranslationPrompt,
    );
    expect(
      translation.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(translation.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
  });

  test('learned parent words hand off to the shared vocabulary flow', () async {
    final flow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      vocabularyLoader: () async => <VocabularyEntry>[
        VocabularyEntry(
          id: 'parent-apple',
          word: 'Apple',
          meaning: 'Quả táo',
          addedAt: DateTime(2026, 8, 18),
          status: VocabularyLearningStatus.learnedWell,
          introducedAt: DateTime(2026, 8, 18, 9),
        ),
      ],
    );
    flow.begin();

    final turn = await flow.handle('Học từ mới');

    expect(turn.promptText, isEmpty);
    expect(turn.continueListening, isFalse);
    expect(
      turn.navigationBeforePrompt?.destination,
      VoiceNavigationDestination.vocabulary,
    );
    expect(flow.stage, MainVoiceAssistantStage.idle);
  });

  test('accepts every D04 topic-learning synonym from Main', () async {
    for (final command in <String>[
      'Học bài',
      'Học theo chủ đề',
      'Học khóa học',
      'Bắt đầu bài học',
    ]) {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        vocabularyLoader: _loadEmptyVocabulary,
      );
      flow.begin();

      final turn = await flow.handle(command);

      expect(turn.promptText, isEmpty, reason: command);
      expect(
        turn.navigationBeforePrompt?.destination,
        VoiceNavigationDestination.topics,
      );
      expect(turn.continueListening, isFalse, reason: command);
      expect(flow.stage, MainVoiceAssistantStage.idle, reason: command);
    }
  });

  test('accepts every D05 vocabulary-learning synonym from Main', () async {
    for (final command in <String>['Học từ mới', 'Học từ', 'Luyện từ']) {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        vocabularyLoader: _loadEmptyVocabulary,
      );
      flow.begin();

      final turn = await flow.handle(command);

      expect(
        turn.navigationBeforePrompt?.destination,
        VoiceNavigationDestination.vocabulary,
        reason: command,
      );
      expect(turn.continueListening, isFalse, reason: command);
      expect(turn.promptText, isEmpty, reason: command);
      expect(flow.stage, MainVoiceAssistantStage.idle, reason: command);
    }
  });

  test(
    'vocabulary content selection belongs to the destination screen',
    () async {
      for (final choice in <String>['Luyện lại', 'Ngôi sao của con']) {
        final flow = MainVoiceAssistantFlow(
          contentLoader: _loadContent,
          vocabularyLoader: _loadReviewAndStarsVocabulary,
        );
        flow.begin();

        final menu = await flow.handle('Học từ mới');
        expect(menu.continueListening, isFalse);
        expect(
          menu.navigationBeforePrompt?.destination,
          VoiceNavigationDestination.vocabulary,
        );
        expect(flow.canHandle(choice), isFalse);
        expect(flow.stage, MainVoiceAssistantStage.idle);
      }
    },
  );

  test('moves to the next sentence in an active lesson', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    expect(
      flow.beginActiveLearning(),
      MainVoiceAssistantFlow.activeLearningPrompt,
    );
    expect(flow.canHandle('Câu tiếp theo'), isTrue);

    final turn = await flow.handle('Câu tiếp theo');
    expect(turn.promptText, 'Mình chuyển sang câu sau nhé.');
    expect(turn.activeLearningCommand, ActiveLearningCommand.nextItem);
    expect(turn.continueListening, isFalse);
  });

  test(
    'generic Vocabulary command returns to its root instead of resuming',
    () async {
      final flow = MainVoiceAssistantFlow()
        ..beginActiveLearning(kind: ActiveLearningModuleKind.vocabulary);

      final turn = await flow.handle('Học Bộ từ vựng');
      expect(turn.activeLearningCommand, ActiveLearningCommand.vocabularyRoot);
      expect(turn.promptText, isEmpty);
      expect(turn.navigationAfterPrompt, isNull);
    },
  );

  test('active lesson prompt offers pause and leaving the lesson', () {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    expect(
      flow.beginActiveLearning(),
      MainVoiceAssistantFlow.activeLearningPrompt,
    );
  });

  test('accepts a natural phrase containing next', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.beginActiveLearning();

    expect(flow.canHandle('Con muốn tiếp theo'), isTrue);
    final turn = await flow.handle('Con muốn tiếp theo');

    expect(turn.activeLearningCommand, ActiveLearningCommand.nextItem);
  });

  test('moves to the previous sentence in an active lesson', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.beginActiveLearning();
    expect(flow.canHandle('Nghe câu trước'), isTrue);

    final turn = await flow.handle('Nghe câu trước');
    expect(turn.promptText, 'Mình nghe lại câu trước nhé');
    expect(turn.activeLearningCommand, ActiveLearningCommand.previousItem);
    expect(turn.continueListening, isFalse);
  });

  test('maps every D07 and D08 command to the active lesson module', () async {
    const cases = <String, ActiveLearningCommand>{
      'Câu tiếp theo': ActiveLearningCommand.nextItem,
      'Câu trước': ActiveLearningCommand.previousItem,
      'Nghe lại': ActiveLearningCommand.replayCurrent,
      'Học lại từ đầu': ActiveLearningCommand.restart,
      'Bài tiếp theo': ActiveLearningCommand.nextLesson,
    };

    for (final entry in cases.entries) {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.beginActiveLearning();

      expect(flow.canHandle(entry.key), isTrue, reason: entry.key);
      final turn = await flow.handle(entry.key);

      expect(turn.activeLearningCommand, entry.value, reason: entry.key);
      expect(turn.continueListening, isFalse, reason: entry.key);
    }
  });

  test('Học bài khác opens Topic selection, not the next lesson', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent)
      ..beginActiveLearning(kind: ActiveLearningModuleKind.listeningLesson);

    final turn = await flow.handle('Học bài khác');

    expect(
      turn.navigationBeforePrompt?.destination,
      VoiceNavigationDestination.topics,
    );
    expect(turn.activeLearningCommand, isNull);
  });

  test(
    'completion choice keeps global destinations ahead of local choices',
    () async {
      for (final phrase in <String>[
        'Chủ đề khác',
        'Bài khác',
        'Học bài khác',
        'Đổi Chủ đề',
        'Bài số 2',
      ]) {
        final stage = phrase == 'Chủ đề khác'
            ? V4CompletionStage.topicEnd
            : V4CompletionStage.lessonEnd;
        final flow = MainVoiceAssistantFlow(childAge: 6)
          ..beginActiveLearning(
            kind: ActiveLearningModuleKind.listeningLesson,
            voiceContext: _CompletionVoiceContext(stage),
          );
        expect(flow.canHandle(phrase), isTrue, reason: phrase);

        final turn = await flow.handle(phrase);
        expect(
          turn.navigationBeforePrompt?.destination,
          VoiceNavigationDestination.topics,
          reason: phrase,
        );
        expect(turn.activeLearningCommand, isNull, reason: phrase);
      }

      for (final entry in <String, VoiceVocabularyTarget>{
        'Ba mẹ đã thêm': VoiceVocabularyTarget.parent,
        'Ngôi sao': VoiceVocabularyTarget.star,
        'Luyện lại': VoiceVocabularyTarget.review,
      }.entries) {
        final flow = MainVoiceAssistantFlow()
          ..beginActiveLearning(
            kind: ActiveLearningModuleKind.listeningLesson,
            voiceContext: const _CompletionVoiceContext(
              V4CompletionStage.lessonEnd,
            ),
          );
        expect(flow.canHandle(entry.key), isTrue, reason: entry.key);
        // A stable partial is enough; the lesson's own choices do not claim it.
        expect(flow.canHandlePartial(entry.key), isTrue, reason: entry.key);

        final turn = await flow.handle(entry.key);
        expect(
          turn.navigationAfterPrompt?.destination,
          VoiceNavigationDestination.vocabulary,
          reason: entry.key,
        );
        expect(
          turn.navigationAfterPrompt?.vocabularyTarget,
          entry.value,
          reason: entry.key,
        );
        expect(turn.activeLearningCommand, isNull, reason: entry.key);
      }
    },
  );

  test(
    'completion choice repeats its question on Continue and keeps local actions',
    () async {
      for (final entry in <String, ActiveLearningCommand>{
        'Bài tiếp theo': ActiveLearningCommand.nextLesson,
        'Học lại bài này': ActiveLearningCommand.restart,
        'Dừng lại': ActiveLearningCommand.stop,
      }.entries) {
        final flow = MainVoiceAssistantFlow()
          ..beginActiveLearning(
            kind: ActiveLearningModuleKind.listeningLesson,
            voiceContext: const _CompletionVoiceContext(
              V4CompletionStage.lessonEnd,
            ),
          );
        final turn = await flow.handle(entry.key);
        expect(turn.activeLearningCommand, entry.value, reason: entry.key);
        expect(turn.navigationBeforePrompt, isNull, reason: entry.key);
        expect(turn.navigationAfterPrompt, isNull, reason: entry.key);
      }

      final flow = MainVoiceAssistantFlow()
        ..beginActiveLearning(
          kind: ActiveLearningModuleKind.listeningLesson,
          voiceContext: const _CompletionVoiceContext(
            V4CompletionStage.lessonEnd,
          ),
        );
      final continueTurn = await flow.handle('Tiếp tục');
      expect(
        continueTurn.promptText,
        const _CompletionVoiceContext(
          V4CompletionStage.lessonEnd,
        ).mainVoicePrompt,
      );
      expect(continueTurn.continueListening, isTrue);
      expect(continueTurn.activeLearningCommand, isNull);
    },
  );

  test('all V4 completion stages retain global MAIN routes', () async {
    for (final stage in V4CompletionStage.values) {
      for (final phrase in <String>[
        'Đổi Chủ đề',
        'Ngôi sao',
        'Dịch tiếng Anh',
        'Học Bộ từ vựng',
      ]) {
        final flow = MainVoiceAssistantFlow(childAge: 6)
          ..beginActiveLearning(
            kind: ActiveLearningModuleKind.listeningLesson,
            voiceContext: _CompletionVoiceContext(stage),
          );
        expect(flow.canHandle(phrase), isTrue, reason: '$stage: $phrase');
        final turn = await flow.handle(phrase);
        expect(
          (turn.navigationBeforePrompt ?? turn.navigationAfterPrompt)
              ?.destination,
          switch (phrase) {
            'Đổi Chủ đề' => VoiceNavigationDestination.topics,
            'Ngôi sao' ||
            'Học Bộ từ vựng' => VoiceNavigationDestination.vocabulary,
            _ => VoiceNavigationDestination.conversation,
          },
          reason: '$stage: $phrase',
        );
        expect(turn.activeLearningCommand, isNull, reason: '$stage: $phrase');
      }
    }
  });

  test(
    'asks the final three-module question before leaving an active lesson',
    () async {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        vocabularyLoader: _loadEmptyVocabulary,
      );
      flow.beginActiveLearning();

      final leaveTurn = await flow.handle('Mình muốn học cái khác');
      expect(leaveTurn.promptText, MasterNavigationContract.translationSwitch);
      expect(leaveTurn.continueListening, isTrue);
      expect(flow.stage, MainVoiceAssistantStage.chooseModuleSwitch);

      final vocabularyTurn = await flow.handle('Mình muốn học từ vựng');
      expect(
        vocabularyTurn.promptText,
        MasterNavigationContract.switchedToVocabulary,
      );
      expect(vocabularyTurn.continueListening, isFalse);
      expect(
        vocabularyTurn.navigationAfterPrompt?.destination,
        VoiceNavigationDestination.vocabulary,
      );
      expect(flow.stage, MainVoiceAssistantStage.idle);
    },
  );

  test('can choose translation after leaving an active lesson', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.beginActiveLearning();
    await flow.handle('Mình muốn học cái khác');

    final translationTurn = await flow.handle('Dịch sang tiếng Anh');
    expect(
      translationTurn.promptText,
      MasterNavigationContract.switchedToTranslation,
    );
    expect(translationTurn.promptSequence.map((utterance) => utterance.text), [
      MasterNavigationContract.switchedToTranslation,
      MasterNavigationContract.translationIntro,
    ]);
    expect(translationTurn.continueListening, isFalse);
    expect(
      translationTurn.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(
      translationTurn.navigationAfterPrompt?.enterMainSpeakingMode,
      isTrue,
    );
    expect(flow.stage, MainVoiceAssistantStage.idle);
  });

  for (final kind in ActiveLearningModuleKind.values) {
    for (final node in [
      ActiveLearningVoiceNode.core,
      ActiveLearningVoiceNode.review,
      ActiveLearningVoiceNode.parent,
      ActiveLearningVoiceNode.star,
    ]) {
      test(
        'transfer from $kind/$node includes translation intro once',
        () async {
          final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
          flow.beginActiveLearning(
            kind: kind,
            voiceContext: _TranslationSourceVoiceContext(node),
          );

          final turn = await flow.handle('Dịch tiếng Anh');

          expect(turn.promptSequence.map((utterance) => utterance.text), [
            MasterNavigationContract.switchedToTranslation,
            MasterNavigationContract.translationIntro,
          ]);
          expect(turn.continueListening, isFalse);
          expect(turn.navigationBeforePrompt, isNull);
          expect(turn.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
          expect(turn.activeLearningCommand, isNull);
        },
      );
    }
  }

  test(
    'missing profile age is handed to Topics without asking for spoken age',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.begin();
      final turn = await flow.handle('Học Chủ đề');
      expect(turn.promptText, isEmpty);
      expect(turn.continueListening, isFalse);
      expect(
        turn.navigationBeforePrompt?.destination,
        VoiceNavigationDestination.topics,
      );
      expect(turn.navigationBeforePrompt?.childAge, isNull);
      expect(flow.canHandle('Con 6 tuổi'), isFalse);
    },
  );

  test('uses the saved age and skips asking age for topic learning', () async {
    final flow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      childAge: 6,
    );

    flow.begin();
    final featureTurn = await flow.handle('Con muốn học theo chủ đề');

    expect(featureTurn.promptText, isEmpty);
    expect(featureTurn.promptText, isNot(contains('mấy tuổi')));
    expect(featureTurn.continueListening, isFalse);
    expect(
      featureTurn.navigationBeforePrompt?.destination,
      VoiceNavigationDestination.topics,
    );
    expect(featureTurn.navigationBeforePrompt?.childAge, 6);
    expect(featureTurn.navigationBeforePrompt?.topicNumber, isNull);
    expect(flow.stage, MainVoiceAssistantStage.idle);
  });

  test('offers topics or vocabulary after leaving speaking practice', () async {
    final vocabularyFlow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      vocabularyLoader: _loadEmptyVocabulary,
    );

    expect(
      vocabularyFlow.beginOtherLearning(),
      MainVoiceAssistantFlow.otherLearningPrompt,
    );
    final vocabularyTurn = await vocabularyFlow.handle('Mình muốn học từ vựng');
    expect(
      vocabularyTurn.promptText,
      MasterNavigationContract.switchedToVocabulary,
    );
    expect(vocabularyTurn.continueListening, isFalse);
    expect(
      vocabularyTurn.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.vocabulary,
    );

    final topicFlow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    topicFlow.beginOtherLearning();
    final topicTurn = await topicFlow.handle('Mình muốn học chủ đề');
    expect(topicTurn.promptText, MasterNavigationContract.switchedToSubject);
    expect(topicTurn.continueListening, isFalse);
    expect(
      topicTurn.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.topics,
    );
    expect(topicFlow.stage, MainVoiceAssistantStage.idle);
  });

  test(
    'understands Vietnamese number words and rejects out-of-range choices',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

      flow.beginTopicSelection(
        childAge: 6,
        topicNumbers: const <int>[1, 2, 3],
        completedTopicNumbers: const <int>[],
      );

      final invalidTopic = await flow.handle('Con chọn chủ đề số mười lăm');
      expect(invalidTopic.continueListening, isTrue);
      expect(invalidTopic.promptText, 'Bạn chọn Chủ đề từ số 1 đến số 10 nhé.');
    },
  );

  test(
    'waits for the topic number instead of committing the Chủ đề partial',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

      flow.beginTopicSelection(
        childAge: 6,
        topicNumbers: const <int>[1, 2, 3],
        completedTopicNumbers: const <int>[],
      );

      expect(flow.canHandlePartial('Chủ đề'), isFalse);
      expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);

      final selected = await flow.handle('Chủ đề số 2');
      expect(
        selected.navigationBeforePrompt?.destination,
        VoiceNavigationDestination.topics,
      );
      expect(selected.navigationBeforePrompt?.topicNumber, 2);
    },
  );

  test('does not treat its own spoken prompts as child selections', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    flow.begin();
    final openingEcho = await flow.handle(
      'Con muốn luyện nói hay học chủ đề nè',
    );
    expect(openingEcho.continueListening, isTrue);
    expect(openingEcho.navigationAfterPrompt, isNull);
    expect(flow.stage, MainVoiceAssistantStage.chooseFeature);

    flow.beginTopicSelection(
      childAge: 6,
      topicNumbers: const <int>[1, 2, 3],
      completedTopicNumbers: const <int>[],
    );
    final topicPromptEcho = await flow.handle(
      'Có 10 Chủ đề. Bạn muốn chọn Chủ đề số mấy?',
    );
    expect(topicPromptEcho.navigationBeforePrompt, isNull);
    expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);
  });

  test(
    'asks before reopening a completed topic after lesson completion',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

      expect(
        flow.beginTopicSelection(
          childAge: 6,
          topicNumbers: const <int>[1, 2, 3],
          completedTopicNumbers: const <int>[3, 5],
        ),
        'Có 10 Chủ đề. Bạn muốn chọn Chủ đề số mấy?',
      );
      expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);
      expect(
        flow.canHandle('Có 10 Chủ đề. Bạn muốn chọn Chủ đề số mấy?'),
        isFalse,
      );

      final completedTopic = await flow.handle('Con chọn chủ đề số 3');
      expect(completedTopic.continueListening, isTrue);
      expect(completedTopic.navigationBeforePrompt, isNull);
      expect(
        completedTopic.promptText,
        'Chủ đề 3 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 3?',
      );
      expect(flow.stage, MainVoiceAssistantStage.confirmReplayTopic);

      final declineTurn = await flow.handle('Chủ đề khác');
      expect(
        declineTurn.promptText,
        'Có 10 Chủ đề. Bạn muốn chọn Chủ đề số mấy?',
      );
      expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);

      await flow.handle('Chủ đề số 3');
      final replayTurn = await flow.handle('Học lại');
      expect(replayTurn.promptText, isEmpty);
      expect(replayTurn.navigationBeforePrompt?.childAge, 6);
      expect(replayTurn.navigationBeforePrompt?.topicNumber, 3);
      expect(replayTurn.navigationBeforePrompt?.relearnTopic, isTrue);
    },
  );

  test('uses ten-topic selection and opens the mic-ready flow', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    expect(
      flow.beginTopicSelection(
        childAge: 6,
        topicNumbers: const <int>[1, 2, 3],
        completedTopicNumbers: const <int>[3],
      ),
      'Có 10 Chủ đề. Bạn muốn chọn Chủ đề số mấy?',
    );

    final locked = await flow.handle('Chủ đề số 11');
    expect(locked.promptText, 'Bạn chọn Chủ đề từ số 1 đến số 10 nhé.');
    expect(locked.continueListening, isTrue);

    final completed = await flow.handle('Chủ đề số 3');
    expect(
      completed.promptText,
      'Chủ đề 3 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 3?',
    );
    expect(completed.continueListening, isTrue);

    final replay = await flow.handle('Học lại');
    expect(replay.promptText, isEmpty);
    expect(replay.continueListening, isFalse);
    expect(replay.navigationBeforePrompt?.topicNumber, 3);
    expect(replay.navigationBeforePrompt?.relearnTopic, isTrue);
  });

  test(
    'completed Course asks for a Topic and opens only that replay branch',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

      expect(
        flow.beginCourseRelearnTopicSelection(
          childAge: 6,
          topicNumbers: const <int>[1, 2, 3],
        ),
        MainVoiceAssistantFlow.courseRelearnTopicPrompt,
      );

      final invalid = await flow.handle('Chủ đề 11');
      expect(invalid.promptText, 'Bạn chọn Chủ đề từ số 1 đến số 10 nhé.');
      expect(invalid.continueListening, isTrue);

      final selected = await flow.handle('Học lại Chủ đề 2');
      expect(selected.promptText, isEmpty);
      expect(selected.continueListening, isFalse);
      expect(selected.navigationBeforePrompt?.topicNumber, 2);
      expect(selected.navigationBeforePrompt?.relearnTopic, isTrue);
      expect(selected.navigationBeforePrompt?.childAge, 6);
    },
  );

  test(
    'accepts named alternatives and rejects yes/no for completed topics',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.beginTopicSelection(
        childAge: 6,
        topicNumbers: const <int>[1, 2, 3],
        completedTopicNumbers: const <int>[3],
      );

      await flow.handle('Chủ đề số 3');
      expect(flow.canHandle('Dạ không'), isFalse);
      expect(flow.canHandle('Có'), isFalse);
      final rejected = await flow.handle('Dạ không');
      expect(rejected.navigationBeforePrompt, isNull);
      expect(flow.stage, MainVoiceAssistantStage.confirmReplayTopic);
      final declineTurn = await flow.handle('Chủ đề khác');
      expect(
        declineTurn.promptText,
        'Có 10 Chủ đề. Bạn muốn chọn Chủ đề số mấy?',
      );
      expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);

      await flow.handle('Chủ đề số 3');
      expect(flow.canHandle('Con muốn học lại'), isTrue);
      final replayTurn = await flow.handle('Con muốn học lại');
      expect(replayTurn.promptText, isEmpty);
      expect(replayTurn.navigationBeforePrompt?.topicNumber, 3);
      expect(replayTurn.navigationBeforePrompt?.relearnTopic, isTrue);
    },
  );

  test(
    'uses the current choice retry instead of treating Mình muốn bài khác as yes',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.beginTopicSelection(
        childAge: 6,
        topicNumbers: const <int>[1, 2, 3],
        completedTopicNumbers: const <int>[3],
      );
      await flow.handle('Chủ đề số 3');

      final retry = await flow.handle('Mình muốn bài khác');

      expect(retry.promptText, contains(flow.currentPrompt));
      expect(retry.continueListening, isTrue);
      expect(retry.navigationBeforePrompt, isNull);
      expect(flow.stage, MainVoiceAssistantStage.confirmReplayTopic);
    },
  );

  test(
    'uses the current choice retry instead of treating Không biết as no',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.beginTopicSelection(
        childAge: 6,
        topicNumbers: const <int>[1, 2, 3],
        completedTopicNumbers: const <int>[3],
      );
      await flow.handle('Chủ đề số 3');

      final retry = await flow.handle('Không biết');

      expect(retry.promptText, contains(flow.currentPrompt));
      expect(retry.continueListening, isTrue);
      expect(retry.navigationBeforePrompt, isNull);
      expect(flow.stage, MainVoiceAssistantStage.confirmReplayTopic);
    },
  );

  test('repeats the current Level count for an invalid topic number', () async {
    final flow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      childAge: 6,
    );
    flow.beginTopicSelection(
      childAge: 6,
      topicNumbers: const <int>[1, 2, 3],
      completedTopicNumbers: const <int>[],
    );

    final retry = await flow.handle('Chủ đề số 15');

    expect(retry.promptText, 'Bạn chọn Chủ đề từ số 1 đến số 10 nhé.');
    expect(retry.continueListening, isTrue);
    expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);
  });

  test(
    'keeps Level selection open after repeated invalid topic numbers',
    () async {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        childAge: 6,
      );
      flow.beginTopicSelection(
        childAge: 6,
        topicNumbers: const <int>[1, 2, 3],
        completedTopicNumbers: const <int>[],
      );
      await flow.handle('Chủ đề số 15');

      final retry = await flow.handle('Chủ đề số 0');

      expect(retry.promptText, 'Bạn chọn Chủ đề từ số 1 đến số 10 nhé.');
      expect(retry.continueListening, isTrue);
      expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);
    },
  );

  test('repeats the current question for an invalid lesson number', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    final content = (await _loadContent()).topic(
      startAge: 6,
      endAge: 7,
      topicNumber: 3,
    );
    flow.beginLessonSelectionForTopic(
      childAge: 6,
      topicNumber: 3,
      topicContent: content,
      completedLessonNumbers: const <int>[],
    );

    final retry = await flow.handle('Bài số 3');

    expect(retry.promptText, contains(flow.currentPrompt));
    expect(retry.continueListening, isTrue);
    expect(flow.stage, MainVoiceAssistantStage.chooseLesson);
  });

  test('pauses for a repeated invalid lesson', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    final content = (await _loadContent()).topic(
      startAge: 6,
      endAge: 7,
      topicNumber: 3,
    );
    flow.beginLessonSelectionForTopic(
      childAge: 6,
      topicNumber: 3,
      topicContent: content,
      completedLessonNumbers: const <int>[],
    );
    await flow.handle('Bài số 3');

    final retry = await flow.handle('Bài số 0');

    expect(retry.promptText, 'Mình tạm dừng nhé.');
    expect(retry.continueListening, isFalse);
    expect(flow.stage, MainVoiceAssistantStage.chooseLesson);
  });

  test('opens an unfinished topic without asking to replay it', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.beginTopicSelection(
      childAge: 6,
      topicNumbers: const <int>[1, 2, 3],
      completedTopicNumbers: const <int>[1, 2],
    );

    final topicTurn = await flow.handle('Con muốn học chủ đề số 3');
    expect(topicTurn.promptText, isEmpty);
    expect(topicTurn.navigationBeforePrompt?.childAge, 6);
    expect(topicTurn.navigationBeforePrompt?.topicNumber, 3);
    expect(topicTurn.navigationBeforePrompt?.relearnTopic, isFalse);
  });

  test('offers the next unfinished lesson from real topic progress', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    final content = (await _loadContent()).topic(
      startAge: 6,
      endAge: 7,
      topicNumber: 3,
    );

    final prompt = flow.beginLessonSelectionForTopic(
      childAge: 6,
      topicNumber: 3,
      topicContent: content,
      completedLessonNumbers: const <int>[1],
    );

    expect(prompt, contains('học lại Bài 1'));
    expect(prompt, contains('học Bài 2'));
    expect(flow.canHandle('Con muốn tiếp tục'), isTrue);

    final turn = await flow.handle('Con muốn tiếp tục');
    expect(turn.continueListening, isFalse);
    expect(turn.navigationAfterPrompt?.topicNumber, 3);
    expect(turn.navigationAfterPrompt?.lessonNumber, 2);
    expect(turn.navigationAfterPrompt?.openLesson, isTrue);
  });

  test(
    'a completed topic offers replay or delegates other topics to the owner',
    () async {
      final content = (await _loadContent()).topic(
        startAge: 6,
        endAge: 7,
        topicNumber: 3,
      );
      for (final replay in [true, false]) {
        final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
        final prompt = flow.beginLessonSelectionForTopic(
          childAge: 6,
          topicNumber: 3,
          topicContent: content,
          completedLessonNumbers: content.lessons
              .map((lesson) => lesson.number)
              .toList(),
        );
        expect(prompt, contains('Chủ đề 3 bạn đã học xong'));
        final turn = await flow.handle(
          replay ? 'Học lại Chủ đề' : 'Chủ đề khác',
        );
        expect(turn.continueListening, isFalse);
        expect(
          turn.navigationBeforePrompt?.destination,
          VoiceNavigationDestination.topics,
        );
        expect(turn.navigationBeforePrompt?.topicNumber, replay ? 3 : null);
        expect(turn.navigationBeforePrompt?.relearnTopic, replay);
        expect(turn.navigationBeforePrompt?.openLesson, isFalse);
      }
    },
  );

  test('confirms before replaying a completed lesson', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    final content = (await _loadContent()).topic(
      startAge: 6,
      endAge: 7,
      topicNumber: 3,
    );
    flow.beginLessonSelectionForTopic(
      childAge: 6,
      topicNumber: 3,
      topicContent: content,
      completedLessonNumbers: const <int>[1],
    );

    final confirmation = await flow.handle('Con chọn bài 1');
    expect(confirmation.continueListening, isTrue);
    expect(confirmation.promptText, contains('học lại Bài 1'));
    expect(confirmation.promptText, contains('học Bài 2'));
    expect(flow.stage, MainVoiceAssistantStage.confirmReplayLesson);

    final replay = await flow.handle('Con muốn học lại');
    expect(replay.continueListening, isFalse);
    expect(replay.navigationAfterPrompt?.lessonNumber, 1);
    expect(replay.navigationAfterPrompt?.relearnLesson, isTrue);
  });
}

class _TranslationSourceVoiceContext implements ActiveLearningVoiceContext {
  const _TranslationSourceVoiceContext(this.mainVoiceNode);

  @override
  final ActiveLearningVoiceNode mainVoiceNode;

  @override
  String get mainVoicePrompt => MasterNavigationContract.coreControlPrompt;
}

class _CompletionVoiceContext
    implements ActiveLearningVoiceContext, ActiveLearningVoiceSelectionContext {
  const _CompletionVoiceContext(this.stage);

  final V4CompletionStage stage;

  @override
  ActiveLearningVoiceNode get mainVoiceNode => ActiveLearningVoiceNode.core;

  @override
  String get mainVoicePrompt => v4CompletionPrompt(
    stage,
    currentLesson: 1,
    nextLesson: 2,
    topicNumber: 1,
  );

  @override
  bool get isMainVoiceChoice => true;

  @override
  ActiveLearningCommand? resolveMainVoiceChoice(String transcript) =>
      switch (const V4CompletionChoiceResolver().resolve(
        transcript,
        stage: stage,
        currentLesson: 1,
        nextLesson: 2,
      )) {
        V4CompletionAction.nextLesson ||
        V4CompletionAction.nextTopic => ActiveLearningCommand.nextLesson,
        V4CompletionAction.relearnCurrentLesson ||
        V4CompletionAction.relearnTopic => ActiveLearningCommand.restart,
        V4CompletionAction.stop => ActiveLearningCommand.stop,
        _ => null,
      };
}

Future<ListeningContentCatalog> _loadThreeTopicContent() async {
  final group = (await _loadContent()).groups.single;
  return ListeningContentCatalog(
    groups: <ListeningContentAgeGroup>[
      ListeningContentAgeGroup(
        startAge: group.startAge,
        endAge: group.endAge,
        topics: <ListeningTopicContent>[
          ListeningTopicContent(
            id: 'a067_t01',
            number: 1,
            titleVi: 'Chủ đề 1',
            titleEn: 'Topic 1',
            lessons: <ListeningLessonContent>[_lesson(1, 'Bài đầu tiên')],
          ),
          ...group.topics,
        ],
      ),
    ],
  );
}

Future<ListeningContentCatalog> _loadContent() async {
  return ListeningContentCatalog(
    groups: <ListeningContentAgeGroup>[
      ListeningContentAgeGroup(
        startAge: 6,
        endAge: 7,
        topics: <ListeningTopicContent>[
          for (var number = 4; number <= 10; number++)
            ListeningTopicContent(
              id: 'fixture-topic-$number',
              number: number,
              titleVi: 'Chủ đề $number',
              titleEn: 'Topic $number',
              lessons: [_lesson(1, 'Bài $number')],
            ),
          ListeningTopicContent(
            id: 'a067_t02',
            number: 2,
            titleVi: 'Gia đình',
            titleEn: 'Family',
            lessons: <ListeningLessonContent>[_lesson(1, 'Người thân')],
          ),
          ListeningTopicContent(
            id: 'a067_t03',
            number: 3,
            titleVi: 'Cặp sách và lớp học',
            titleEn: 'School Bag and Classroom',
            lessons: <ListeningLessonContent>[
              _lesson(1, 'Đồ dùng học tập'),
              _lesson(2, 'Trong lớp học'),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<List<VocabularyEntry>> _loadEmptyVocabulary() async =>
    const <VocabularyEntry>[];

Future<List<VocabularyEntry>> _loadReviewAndStarsVocabulary() async =>
    (await _loadVocabularyAcrossCollections())
        .where((entry) => entry.collection != VocabularyCollection.saved)
        .toList(growable: false);

Future<List<VocabularyEntry>> _loadVocabularyAcrossCollections() async =>
    <VocabularyEntry>[
      VocabularyEntry(
        id: 'parent-apple',
        word: 'Apple',
        meaning: 'Quả táo',
        addedAt: DateTime(2026, 8, 18),
      ),
      VocabularyEntry(
        id: 'review-book',
        word: 'Open your book',
        meaning: 'Mở sách ra',
        addedAt: DateTime(2026, 8, 18),
        collection: VocabularyCollection.review,
      ),
      VocabularyEntry(
        id: 'star-morning',
        word: 'Good morning',
        meaning: 'Chào buổi sáng',
        addedAt: DateTime(2026, 8, 18),
        collection: VocabularyCollection.star,
      ),
    ];

ListeningLessonContent _lesson(int number, String title) {
  return ListeningLessonContent(
    id: 'lesson-$number',
    number: number,
    titleVi: title,
    titleEn: title,
    intro: '',
    outro: '',
    estimatedMinutes: 3,
    sentences: const <ListeningSentenceContent>[],
  );
}
