import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/v4_completion_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/active_learning_command_resolver.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every literal MAIN sample hands off to the correct existing module',
    () async {
      for (final entry in {
        'OPEN_SUBJECT': VoiceNavigationDestination.topics,
        'OPEN_VOCAB': VoiceNavigationDestination.vocabulary,
        'OPEN_TRANSLATE': VoiceNavigationDestination.conversation,
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
    'numbers are scoped to the current menu and cannot come from free speech',
    () async {
      for (final text in [
        'Từ vựng',
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
      resolver.resolve('Học lại', node: ActiveLearningVoiceNode.vocabularyMenu),
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
      isNull,
    );
    expect(
      resolver.resolve(
        'Ba mẹ',
        node: ActiveLearningVoiceNode.parentAlternatives,
      ),
      isNull,
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
        'Ngôi sao',
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
      resolver.resolve('Nội dung khác', node: ActiveLearningVoiceNode.parent),
      isNull,
    );
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
