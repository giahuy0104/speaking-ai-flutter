import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/v4_completion_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/active_learning_command_resolver.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/main_assistant_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/controlled_speech_lexicon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Core and Challenge use the approved MAIN questions', () {
    expect(
      MasterNavigationContract.coreControlPrompt,
      'Bạn muốn nghe lại, câu trước, hay câu sau?',
    );
    expect(
      MasterNavigationContract.nextItemPrompt,
      'Mình chuyển sang câu sau nhé.',
    );
    expect(
      MasterNavigationContract.challengeControlPrompt,
      'Bạn muốn nghe lại hay dừng lại?',
    );
  });

  test(
    'sentence owner chooses the lead after validating its boundary',
    () async {
      for (final kind in [
        ActiveLearningModuleKind.listeningLesson,
        ActiveLearningModuleKind.vocabulary,
      ]) {
        for (final phrase in ['Câu trước', 'Câu sau']) {
          final flow = MainVoiceAssistantFlow();
          flow.beginActiveLearning(
            kind: kind,
            voiceContext: const _VoiceContext(
              ActiveLearningVoiceNode.core,
              MasterNavigationContract.coreControlPrompt,
            ),
          );
          final turn = await flow.handle(phrase);
          expect(turn.promptText, isEmpty);
          expect(
            turn.activeLearningCommand,
            phrase == 'Câu trước'
                ? ActiveLearningCommand.previousItem
                : ActiveLearningCommand.nextItem,
          );
        }
      }
    },
  );

  test(
    'Review allows each sentence choice without opening other activities',
    () {
      const resolver = ActiveLearningCommandResolver();
      for (final entry in <String, ActiveLearningCommand>{
        'LISTEN_AGAIN': ActiveLearningCommand.replayCurrent,
        'PREVIOUS_ITEM': ActiveLearningCommand.previousItem,
        'NEXT_ITEM': ActiveLearningCommand.nextItem,
      }.entries) {
        for (final phrase in MasterNavigationContract.phrases[entry.key]!) {
          expect(
            resolver.resolve(
              phrase,
              node: ActiveLearningVoiceNode.review,
              state: ControlledSpeechState.vocabulary,
            ),
            entry.value,
            reason: phrase,
          );
        }
      }
      expect(
        resolver.resolve('Bài tiếp theo', node: ActiveLearningVoiceNode.review),
        isNull,
      );
    },
  );

  test(
    'every literal MAIN sample hands off to the correct existing module',
    () async {
      for (final entry in {
        'OPEN_SUBJECT': VoiceNavigationDestination.topics,
        'OPEN_VOCAB': VoiceNavigationDestination.vocabulary,
        'OPEN_TRANSLATE': VoiceNavigationDestination.conversation,
        'TRANSLATE_CONTINUOUS': VoiceNavigationDestination.conversation,
      }.entries) {
        for (final text in MasterNavigationContract.phrases[entry.key]!) {
          final flow = MainVoiceAssistantFlow(childAge: 6)..begin();
          final turn = await flow.handle(text);
          final intent =
              turn.navigationBeforePrompt ?? turn.navigationAfterPrompt;
          expect(intent?.destination, entry.value, reason: text);
          expect(turn.continueListening, isFalse, reason: text);
        }
      }
    },
  );

  test('continuous translation stops only on the approved exact phrase', () {
    expect(MasterNavigationContract.isTranslationStop('Dừng lại'), isTrue);
    expect(MasterNavigationContract.isTranslationStop('  dỪnG LạI! '), isTrue);
    for (final text in <String>[
      'Dừng dịch',
      'Dừng dịch liên tục',
      'Ngừng',
      'Thôi dừng lại',
      'Mình muốn dừng',
      'Không dịch nữa',
      'Thoát dịch',
    ]) {
      expect(
        MasterNavigationContract.isTranslationStop(text),
        isFalse,
        reason: text,
      );
    }
  });

  test('SKIP_SONG is separate and excludes sentence-shaped commands', () async {
    const resolver = ActiveLearningCommandResolver();
    for (final text in MasterNavigationContract.phrases['SKIP_SONG']!) {
      expect(
        resolver.resolve(text, node: ActiveLearningVoiceNode.song),
        ActiveLearningCommand.nextItem,
        reason: text,
      );
    }
    for (final text in <String>[
      'Bỏ câu này nhé',
      'Chuyển sang câu khác',
      'Mình không muốn nghe câu này',
    ]) {
      expect(
        resolver.resolve(text, node: ActiveLearningVoiceNode.song),
        isNull,
        reason: text,
      );
    }

    final flow = MainVoiceAssistantFlow();
    expect(
      flow.beginActiveLearning(
        kind: ActiveLearningModuleKind.listeningLesson,
        voiceContext: const _VoiceContext(
          ActiveLearningVoiceNode.song,
          MasterNavigationContract.songControlPrompt,
        ),
      ),
      MasterNavigationContract.songControlPrompt,
    );
    final skipped = await flow.handle('Bỏ qua bài hát');
    expect(skipped.promptText, MasterNavigationContract.songSkipped);
    expect(skipped.activeLearningCommand, ActiveLearningCommand.nextItem);

    final replayed = await flow.handle('Nghe lại');
    expect(replayed.promptText, MasterNavigationContract.songReplay);
    expect(replayed.promptAudioKey, MainAssistantAudioKeys.songReplay);
    expect(replayed.activeLearningCommand, ActiveLearningCommand.replayCurrent);
  });

  test(
    'song fallback repeats once then resumes the current position',
    () async {
      final flow = MainVoiceAssistantFlow();
      flow.beginActiveLearning(
        kind: ActiveLearningModuleKind.listeningLesson,
        voiceContext: const _VoiceContext(
          ActiveLearningVoiceNode.song,
          MasterNavigationContract.songControlPrompt,
        ),
      );

      final first = await flow.handle('Hôm nay trời nắng');
      expect(first.promptText, MasterNavigationContract.songControlPrompt);
      expect(first.continueListening, isTrue);
      final second = await flow.handle('Mình đang ngồi đây');
      expect(second.promptText, MasterNavigationContract.keepCurrentContent);
      expect(second.activeLearningCommand, ActiveLearningCommand.resume);
      expect(second.continueListening, isFalse);
    },
  );

  test(
    'every active learning node resumes after the second fallback',
    () async {
      for (final node in <ActiveLearningVoiceNode>[
        ActiveLearningVoiceNode.core,
        ActiveLearningVoiceNode.challenge,
        ActiveLearningVoiceNode.review,
        ActiveLearningVoiceNode.today,
        ActiveLearningVoiceNode.parent,
        ActiveLearningVoiceNode.star,
      ]) {
        final flow = MainVoiceAssistantFlow();
        const prompt = MasterNavigationContract.coreControlPrompt;
        flow.beginActiveLearning(
          kind: ActiveLearningModuleKind.listeningLesson,
          voiceContext: _VoiceContext(node, prompt),
        );

        final first = await flow.handle('Hôm nay trời nắng');
        expect(first.promptText, prompt, reason: '$node first fallback');
        expect(first.continueListening, isTrue, reason: '$node first fallback');

        final second = await flow.handle('Mình đang ngồi đây');
        expect(
          second.promptText,
          MasterNavigationContract.keepCurrentContent,
          reason: '$node second fallback',
        );
        expect(
          second.activeLearningCommand,
          ActiveLearningCommand.resume,
          reason: '$node second fallback',
        );
        expect(second.continueListening, isFalse);
      }
    },
  );

  test(
    'all explicit module samples work while another module is active',
    () async {
      final cases =
          <
            ({
              String intent,
              ActiveLearningModuleKind source,
              VoiceNavigationDestination destination,
              String confirmation,
            })
          >[
            (
              intent: 'OPEN_SUBJECT',
              source: ActiveLearningModuleKind.vocabulary,
              destination: VoiceNavigationDestination.topics,
              confirmation: MasterNavigationContract.switchedToSubject,
            ),
            (
              intent: 'OPEN_VOCAB',
              source: ActiveLearningModuleKind.listeningLesson,
              destination: VoiceNavigationDestination.vocabulary,
              confirmation: MasterNavigationContract.switchedToVocabulary,
            ),
            (
              intent: 'OPEN_TRANSLATE',
              source: ActiveLearningModuleKind.listeningLesson,
              destination: VoiceNavigationDestination.conversation,
              confirmation: MasterNavigationContract.switchedToTranslation,
            ),
            (
              intent: 'TRANSLATE_CONTINUOUS',
              source: ActiveLearningModuleKind.vocabulary,
              destination: VoiceNavigationDestination.conversation,
              confirmation: MasterNavigationContract.switchedToTranslation,
            ),
          ];

      for (final testCase in cases) {
        for (final text in MasterNavigationContract.phrases[testCase.intent]!) {
          final flow = MainVoiceAssistantFlow()
            ..beginActiveLearning(kind: testCase.source);
          final turn = await flow.handle(text);
          expect(turn.promptText, testCase.confirmation, reason: text);
          expect(
            turn.navigationAfterPrompt?.destination,
            testCase.destination,
            reason: text,
          );
          expect(turn.continueListening, isFalse, reason: text);
          expect(flow.stage, MainVoiceAssistantStage.idle, reason: text);
        }
      }
    },
  );

  test(
    'vague module requests ask, retry once, then keep current content',
    () async {
      for (final text
          in MasterNavigationContract.phrases['SWITCH_MODULE_MENU']!) {
        final flow = MainVoiceAssistantFlow()
          ..beginActiveLearning(kind: ActiveLearningModuleKind.listeningLesson);
        final question = await flow.handle(text);
        expect(
          question.promptText,
          MasterNavigationContract.translationSwitch,
          reason: text,
        );
        expect(flow.stage, MainVoiceAssistantStage.chooseModuleSwitch);

        final first = await flow.handle('Hôm nay trời nắng');
        expect(
          first.promptText,
          MasterNavigationContract.translationSwitch,
          reason: text,
        );
        final second = await flow.handle('Mình đang ngồi đây');
        expect(
          second.promptText,
          MasterNavigationContract.keepCurrentContent,
          reason: text,
        );
        expect(second.activeLearningCommand, ActiveLearningCommand.resume);
      }
    },
  );

  test(
    'selecting the current module resumes it with the approved wording',
    () async {
      final subjectFlow = MainVoiceAssistantFlow()
        ..beginActiveLearning(kind: ActiveLearningModuleKind.listeningLesson);
      final subjectTurn = await subjectFlow.handle('Học Chủ đề');
      expect(subjectTurn.promptText, MasterNavigationContract.continueSubject);
      expect(subjectTurn.activeLearningCommand, ActiveLearningCommand.resume);
      expect(subjectTurn.navigationAfterPrompt, isNull);

      final vocabularyFlow = MainVoiceAssistantFlow()
        ..beginActiveLearning(kind: ActiveLearningModuleKind.vocabulary);
      final vocabularyTurn = await vocabularyFlow.handle('Bộ từ vựng');
      expect(
        vocabularyTurn.promptText,
        MasterNavigationContract.continueVocabulary,
      );
      expect(
        vocabularyTurn.activeLearningCommand,
        ActiveLearningCommand.resume,
      );
      expect(vocabularyTurn.navigationAfterPrompt, isNull);
    },
  );

  test(
    'MAIN does not guess from an embedded destination or closed-choice answer',
    () async {
      for (final text in [
        'Học tiếp',
        'Học lại',
        'Có',
        'Không',
        'Mình không muốn học Chủ đề',
        'Hôm nay mình học từ vựng ở trường',
        'Dịch tiếng Anh hay học Chủ đề',
        'Mình muốn dịch câu học từ vựng',
        'Mình không muốn luyện nói',
        'Mình đang nói chuyện với ba mẹ',
      ]) {
        final flow = MainVoiceAssistantFlow()..begin();
        expect(flow.canHandle(text), isFalse, reason: text);
        expect(flow.canHandlePartial(text), isFalse, reason: text);
        final turn = await flow.handle(text);
        expect(turn.navigationBeforePrompt, isNull, reason: text);
        expect(turn.navigationAfterPrompt, isNull, reason: text);
      }
    },
  );

  test(
    'after stop and switch menus accept continue translation in their own state',
    () async {
      for (final text
          in MasterNavigationContract.phrases['CONTINUE_TRANSLATE']!) {
        for (final afterStop in [true, false]) {
          final flow = MainVoiceAssistantFlow();
          afterStop
              ? flow.beginAfterTranslationStop()
              : flow.beginOtherLearning();
          final turn = await flow.handle(text);
          expect(
            turn.navigationAfterPrompt?.enterMainSpeakingMode,
            isTrue,
            reason: text,
          );
          expect(turn.promptText, 'Mình tiếp tục nhé.');
        }
      }
    },
  );

  test(
    'translation switch fallback keeps the current translation session',
    () async {
      final flow = MainVoiceAssistantFlow()..beginOtherLearning();

      final first = await flow.handle('Hôm nay trời nắng');
      expect(first.promptText, MasterNavigationContract.translationSwitch);
      expect(first.continueListening, isTrue);

      final second = await flow.handle('Mình đang ngồi đây');
      expect(second.promptText, MasterNavigationContract.keepCurrentContent);
      expect(
        second.navigationAfterPrompt?.destination,
        VoiceNavigationDestination.conversation,
      );
      expect(second.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
      expect(flow.stage, MainVoiceAssistantStage.idle);
    },
  );

  test(
    'numbers are scoped to the current menu and cannot come from free speech',
    () async {
      for (final text in [
        'Con 6 tuổi',
        'Bài 2',
        'Level 2',
        'Mình có 2 con mèo',
        'Chủ đề 1 hoặc 2',
      ]) {
        final flow = MainVoiceAssistantFlow();
        flow.beginLevelTopicSelection(
          childAge: 6,
          levelNumber: 1,
          topicNumbers: [1, 2, 3],
          completedTopicNumbers: [],
          announceLevel: false,
        );
        expect(flow.canHandle(text), isFalse, reason: text);
        final turn = await flow.handle(text);
        expect(turn.navigationBeforePrompt, isNull, reason: text);
        expect(turn.navigationAfterPrompt, isNull, reason: text);
        expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);
      }
    },
  );

  test(
    'paused choice retains its question and allowed topics for reactivation',
    () async {
      final flow = MainVoiceAssistantFlow();
      final prompt = flow.beginLevelTopicSelection(
        childAge: 6,
        levelNumber: 2,
        topicNumbers: [4, 5, 6],
        completedTopicNumbers: [4],
        announceLevel: false,
      );
      expect(flow.silenceRetryPrompt, prompt);
      expect(flow.silenceExitPrompt, 'Mình tạm dừng nhé.');
      flow.pauseChoice();
      expect(flow.begin(), prompt);
      final invalid = await flow.handle('Chủ đề 1');
      expect(invalid.navigationBeforePrompt, isNull);
      expect(invalid.promptText, 'Level này có 3 Chủ đề. Bạn chọn lại nhé.');
    },
  );

  test('every navigation state pauses after the second silence', () async {
    final flow = MainVoiceAssistantFlow();

    flow.beginOtherLearning();
    var turn = flow.handleSilenceExit();
    expect(turn.promptText, MasterNavigationContract.pause);
    expect(turn.navigationAfterPrompt, isNull);
    expect(turn.activeLearningCommand, isNull);

    flow.beginActiveLearning(kind: ActiveLearningModuleKind.vocabulary);
    await flow.handle('Mình muốn học cái khác');
    turn = flow.handleSilenceExit();
    expect(turn.promptText, MasterNavigationContract.pause);
    expect(turn.navigationAfterPrompt, isNull);
    expect(turn.activeLearningCommand, isNull);

    flow.beginActiveLearning(
      kind: ActiveLearningModuleKind.listeningLesson,
      voiceContext: const _VoiceContext(
        ActiveLearningVoiceNode.song,
        'Bạn muốn nghe lại hay nghe tiếp?',
      ),
    );
    turn = flow.handleSilenceExit();
    expect(turn.promptText, MasterNavigationContract.pause);
    expect(turn.navigationAfterPrompt, isNull);
    expect(turn.activeLearningCommand, ActiveLearningCommand.stop);
  });

  test('vocabulary choices are closed and replay keeps its scope', () {
    const resolver = ActiveLearningCommandResolver();
    expect(
      resolver.resolve('Ba mẹ', node: ActiveLearningVoiceNode.vocabularyMenu),
      ActiveLearningCommand.vocabularyParentAdded,
    );
    expect(
      resolver.resolve(
        'Học tiếp',
        node: ActiveLearningVoiceNode.vocabularyMenu,
      ),
      isNull,
    );
    expect(
      resolver.resolve(
        'Luyện lại',
        node: ActiveLearningVoiceNode.vocabularyMenu,
      ),
      ActiveLearningCommand.vocabularyPracticeAgain,
    );
    expect(
      resolver.resolve('Học lại', node: ActiveLearningVoiceNode.todayEnd),
      ActiveLearningCommand.restart,
    );
    expect(
      resolver.resolve(
        'Nghe lại tất cả',
        node: ActiveLearningVoiceNode.listEnd,
      ),
      ActiveLearningCommand.restart,
    );
    expect(
      resolver.resolve(
        'Học lại',
        node: ActiveLearningVoiceNode.reviewAlternatives,
      ),
      isNull,
    );
    expect(
      resolver.resolve(
        'Ngôi sao',
        node: ActiveLearningVoiceNode.starAlternatives,
      ),
      ActiveLearningCommand.vocabularyStars,
    );
    expect(
      resolver.resolve(
        'Ba mẹ',
        node: ActiveLearningVoiceNode.parentAlternatives,
      ),
      ActiveLearningCommand.vocabularyParentAdded,
    );
    expect(
      resolver.resolve('Tiếp theo', node: ActiveLearningVoiceNode.blockEnd),
      ActiveLearningCommand.resume,
    );
  });

  test('unsupported activity commands cannot escape to generic grammar', () {
    const resolver = ActiveLearningCommandResolver();
    for (final node in [
      ActiveLearningVoiceNode.review,
      ActiveLearningVoiceNode.challenge,
    ]) {
      for (final text in [
        'Câu tiếp theo',
        'Câu trước',
        'Bỏ qua',
        'Học lại',
        'Học nội dung khác',
        'Bài trước',
        'Bài tiếp theo',
      ]) {
        expect(
          resolver.resolve(text, node: node),
          isNull,
          reason: '$node: $text',
        );
      }
      expect(
        resolver.resolve('Nghe lại', node: node),
        ActiveLearningCommand.replayCurrent,
      );
    }
    expect(
      resolver.resolve('Bỏ qua', node: ActiveLearningVoiceNode.today),
      isNull,
    );
    expect(
      resolver.resolve('Câu tiếp theo', node: ActiveLearningVoiceNode.today),
      isNull,
    );
    expect(
      resolver.resolve(
        'Câu tiếp theo',
        node: ActiveLearningVoiceNode.todayAfterEnVi,
      ),
      ActiveLearningCommand.nextItem,
    );
    expect(
      resolver.resolve('Bỏ qua', node: ActiveLearningVoiceNode.todayAfterEnVi),
      isNull,
    );
    expect(
      resolver.resolve('Nội dung khác', node: ActiveLearningVoiceNode.parent),
      isNull,
    );
  });

  test('ambiguous next means next Core item, not resume current item', () {
    const resolver = ActiveLearningCommandResolver();
    expect(
      resolver.resolve('Tiếp theo', node: ActiveLearningVoiceNode.core),
      ActiveLearningCommand.nextItem,
    );
    expect(
      resolver.resolve('Tiếp theo', node: ActiveLearningVoiceNode.parent),
      ActiveLearningCommand.nextItem,
    );
    expect(
      resolver.resolve('Tiếp theo', node: ActiveLearningVoiceNode.challenge),
      isNull,
    );
  });

  test('Challenge also accepts the global Continue command', () async {
    final flow = MainVoiceAssistantFlow();
    const context = _VoiceContext(
      ActiveLearningVoiceNode.challenge,
      MasterNavigationContract.challengeControlPrompt,
    );

    expect(
      flow.beginActiveLearning(
        kind: ActiveLearningModuleKind.listeningLesson,
        voiceContext: context,
      ),
      MasterNavigationContract.challengeControlPrompt,
    );
    final turn = await flow.handle('Tiếp tục');
    expect(turn.activeLearningCommand, ActiveLearningCommand.resume);
    expect(turn.promptText, isEmpty);
    expect(turn.continueListening, isFalse);
  });

  test('vocabulary destinations are global at every learning node', () {
    const resolver = ActiveLearningCommandResolver();
    for (final node in ActiveLearningVoiceNode.values) {
      expect(
        resolver.resolve('Ba mẹ đã thêm', node: node),
        ActiveLearningCommand.vocabularyParentAdded,
        reason: '$node parent',
      );
      expect(
        resolver.resolve('Ngôi sao', node: node),
        ActiveLearningCommand.vocabularyStars,
        reason: '$node star',
      );
      expect(
        resolver.resolve('Luyện lại', node: node),
        ActiveLearningCommand.vocabularyPracticeAgain,
        reason: '$node review',
      );
    }
  });

  test('Subject can jump directly to a vocabulary destination', () async {
    final flow = MainVoiceAssistantFlow()
      ..beginActiveLearning(
        kind: ActiveLearningModuleKind.listeningLesson,
        voiceContext: const _VoiceContext(
          ActiveLearningVoiceNode.core,
          MasterNavigationContract.coreControlPrompt,
        ),
      );

    final turn = await flow.handle('Ngôi sao');

    expect(turn.promptText, isEmpty);
    expect(
      turn.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.vocabulary,
    );
    expect(
      turn.navigationAfterPrompt?.vocabularyTarget,
      VoiceVocabularyTarget.star,
    );
  });

  test('lesson and level change phrases reopen Topic selection', () async {
    for (final phrase in ['Bài khác', 'Level khác', 'Chủ đề khác']) {
      final flow = MainVoiceAssistantFlow(childAge: 6)
        ..beginActiveLearning(
          kind: ActiveLearningModuleKind.listeningLesson,
          voiceContext: const _VoiceContext(
            ActiveLearningVoiceNode.core,
            MasterNavigationContract.coreControlPrompt,
          ),
        );

      final turn = await flow.handle(phrase);

      expect(
        turn.navigationBeforePrompt?.destination,
        VoiceNavigationDestination.topics,
        reason: phrase,
      );
      expect(turn.navigationBeforePrompt?.topicNumber, isNull, reason: phrase);
    }
  });

  test(
    'active context supplies help and stop without touching study data',
    () async {
      final flow = MainVoiceAssistantFlow();
      const context = _VoiceContext(
        ActiveLearningVoiceNode.reviewAlternatives,
        'Mình đã luyện xong rồi. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?',
      );
      expect(
        flow.beginActiveLearning(
          kind: ActiveLearningModuleKind.vocabulary,
          voiceContext: context,
        ),
        context.mainVoicePrompt,
      );
      final help = await flow.handle('Phải nói gì');
      expect(help.promptText, context.mainVoicePrompt);
      expect(help.activeLearningCommand, isNull);
      final invalid = await flow.handle('Học lại');
      expect(invalid.activeLearningCommand, isNull);
      expect(invalid.promptText, contains(context.mainVoicePrompt));
      final stop = await flow.handle('Cho mình nghỉ một chút');
      expect(stop.activeLearningCommand, ActiveLearningCommand.stop);
      expect(stop.navigationAfterPrompt, isNull);
    },
  );

  test(
    'MAIN echo repeats the current navigation question instead of the legacy menu',
    () async {
      for (final context in const [
        _VoiceContext(
          ActiveLearningVoiceNode.core,
          MasterNavigationContract.coreControlPrompt,
        ),
        _VoiceContext(
          ActiveLearningVoiceNode.core,
          'Bạn muốn học Bài 2 hay học lại Bài 1?',
        ),
        _VoiceContext(
          ActiveLearningVoiceNode.challenge,
          'Bạn muốn tiếp tục, nghe lại hay dừng lại?',
        ),
        _VoiceContext(
          ActiveLearningVoiceNode.reviewAlternatives,
          'Mình đã luyện xong rồi. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?',
        ),
      ]) {
        final flow = MainVoiceAssistantFlow();
        flow.beginActiveLearning(voiceContext: context);

        final turn = await flow.handle(context.mainVoicePrompt);

        expect(turn.promptText, context.mainVoicePrompt);
        expect(turn.continueListening, isTrue);
        expect(turn.activeLearningCommand, isNull);
        expect(turn.navigationBeforePrompt, isNull);
        expect(turn.navigationAfterPrompt, isNull);
        expect(flow.stage, MainVoiceAssistantStage.activeLearning);
        expect(flow.silenceRetryPrompt, context.mainVoicePrompt);
      }
    },
  );

  test(
    'FINAL T09 repairs ambiguous lesson continuation and rejects locked numbers',
    () {
      const resolver = V4CompletionChoiceResolver();
      for (final text in [
        'Học tiếp',
        'Có',
        'Không',
        'Bài 8',
        'Học lại Bài 8',
      ]) {
        expect(
          resolver.resolve(
            text,
            stage: V4CompletionStage.lessonEnd,
            currentLesson: 1,
            nextLesson: 2,
          ),
          isNull,
          reason: text,
        );
      }
      expect(
        resolver.resolve(
          '2',
          stage: V4CompletionStage.lessonEnd,
          currentLesson: 1,
          nextLesson: 2,
        ),
        V4CompletionAction.nextLesson,
      );
      expect(
        resolver.resolve(
          'Học lại',
          stage: V4CompletionStage.lessonEnd,
          currentLesson: 1,
          nextLesson: 2,
        ),
        V4CompletionAction.relearnCurrentLesson,
      );
      expect(
        resolver.resolve(
          'Level 3',
          stage: V4CompletionStage.nextLevel,
          nextLevel: 2,
        ),
        isNull,
      );
    },
  );
}

class _VoiceContext implements ActiveLearningVoiceContext {
  const _VoiceContext(this.mainVoiceNode, this.mainVoicePrompt);
  @override
  final ActiveLearningVoiceNode mainVoiceNode;
  @override
  final String mainVoicePrompt;
}
