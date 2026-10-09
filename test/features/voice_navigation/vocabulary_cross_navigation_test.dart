import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/controlled_speech_lexicon.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const targets = <String, VoiceVocabularyTarget>{
    'OPEN_PARENT': VoiceVocabularyTarget.parent,
    'OPEN_STAR': VoiceVocabularyTarget.star,
    'OPEN_REVIEW': VoiceVocabularyTarget.review,
  };

  test(
    'MAIN menus accept and dispatch every direct vocabulary alias',
    () async {
      final content = await AssetListeningContentRepository().load();
      final topic = content.groups.first.topics.first;
      final menus = <String, Future<void> Function(MainVoiceAssistantFlow)>{
        'translation idle': (flow) async {
          flow.begin();
        },
        'translation active': (flow) async {
          flow.beginOtherLearning();
        },
        'translation stopped': (flow) async {
          flow.beginAfterTranslationStop();
        },
        'module switch': (flow) async {
          flow.beginActiveLearning(
            kind: ActiveLearningModuleKind.listeningLesson,
          );
          await flow.handle('Mở phần khác');
          expect(flow.stage, MainVoiceAssistantStage.chooseModuleSwitch);
        },
        'topic selection': (flow) async {
          flow.beginTopicSelection(
            childAge: 3,
            topicNumbers: [1, 2],
            completedTopicNumbers: [],
          );
        },
        'completed topic': (flow) async {
          flow.beginTopicSelection(
            childAge: 3,
            topicNumbers: [1, 2],
            completedTopicNumbers: [1],
          );
          await flow.handle('Chủ đề 1');
          expect(flow.stage, MainVoiceAssistantStage.confirmReplayTopic);
        },
        'course replay': (flow) async {
          flow.beginCourseRelearnTopicSelection(
            childAge: 3,
            topicNumbers: [1, 2],
          );
        },
        'lesson selection': (flow) async {
          flow.beginLessonSelectionForTopic(
            childAge: 3,
            topicNumber: 1,
            topicContent: topic,
            completedLessonNumbers: [],
          );
        },
      };
      for (final menu in menus.entries) {
        for (final target in targets.entries) {
          for (final phrase in MasterNavigationContract.phrases[target.key]!) {
            final flow = MainVoiceAssistantFlow(childAge: 3);
            await menu.value(flow);
            expect(
              flow.canHandle(phrase),
              isTrue,
              reason: '${menu.key}: $phrase',
            );
            expect(
              flow.canHandlePartial(phrase),
              isTrue,
              reason: '${menu.key}: $phrase',
            );
            final turn = await flow.handle(phrase);
            expect(
              turn.navigationAfterPrompt?.destination,
              VoiceNavigationDestination.vocabulary,
            );
            expect(turn.navigationAfterPrompt?.vocabularyTarget, target.value);
            expect(turn.promptText, isEmpty);
            expect(turn.activeLearningCommand, isNull);
            expect(turn.continueListening, isFalse);
          }
        }
        for (final text in [
          'Ba',
          'Ngôi',
          'Luyện',
          'Ngôi sao hay Luyện lại',
          'Tôi nhìn thấy ngôi sao',
          'Ba mẹ đã thêm hay học Chủ đề',
        ]) {
          final flow = MainVoiceAssistantFlow(childAge: 3);
          await menu.value(flow);
          expect(
            flow.canHandlePartial(text),
            isFalse,
            reason: '${menu.key}: $text',
          );
        }
        final echo = MainVoiceAssistantFlow(childAge: 3);
        await menu.value(echo);
        final prompt = echo.currentPrompt;
        expect(echo.canHandlePartial(prompt), isFalse);
        final repeated = await echo.handle(prompt);
        expect(repeated.navigationAfterPrompt, isNull);
        expect(repeated.navigationBeforePrompt, isNull);
      }
    },
  );

  test('all listening voice nodes retain direct section transfer', () async {
    for (final node in [
      ActiveLearningVoiceNode.intro,
      ActiveLearningVoiceNode.core,
      ActiveLearningVoiceNode.challenge,
      ActiveLearningVoiceNode.review,
      ActiveLearningVoiceNode.song,
    ]) {
      for (final entry in targets.entries) {
        final flow = MainVoiceAssistantFlow()
          ..beginActiveLearning(
            kind: ActiveLearningModuleKind.listeningLesson,
            voiceContext: _Context(node),
          );
        final turn = await flow.handle(
          MasterNavigationContract.phrases[entry.key]!.first,
        );
        expect(turn.navigationAfterPrompt?.vocabularyTarget, entry.value);
      }
    }
  });

  test(
    'navigation grammar excludes free translation and unfinished commands',
    () {
      const resolver = VoiceNavigationIntentResolver();
      const lexicon = ControlledSpeechLexicon();
      for (final entry in targets.entries) {
        for (final text in MasterNavigationContract.phrases[entry.key]!) {
          expect(resolver.resolve(text)?.vocabularyTarget, entry.value);
          for (final state in [
            ControlledSpeechState.root,
            ControlledSpeechState.translateMenu,
            ControlledSpeechState.translationResult,
            ControlledSpeechState.course,
          ]) {
            expect(
              lexicon.resolve(text, state: state)?.intent,
              switch (entry.value) {
                VoiceVocabularyTarget.parent =>
                  ControlledSpeechIntent.vocabularyParentAdded,
                VoiceVocabularyTarget.star =>
                  ControlledSpeechIntent.vocabularyStars,
                VoiceVocabularyTarget.review =>
                  ControlledSpeechIntent.vocabularyPracticeAgain,
              },
            );
          }
        }
      }
      for (final text in [
        'Tôi nhìn thấy ngôi sao',
        'Ba mẹ đã thêm một câu cho tôi',
        'Tôi muốn luyện lại đoạn văn',
        'Ngôi sao hay Luyện lại',
        'Ba',
        'Ngôi',
        'Luyện',
      ]) {
        expect(resolver.resolve(text), isNull, reason: text);
        expect(
          resolver.resolve(text, allowShortDirectCommand: false),
          isNull,
          reason: text,
        );
      }
      expect(
        resolver.resolve('Ngôi sao', allowShortDirectCommand: false),
        isNull,
      );
      expect(
        resolver
            .resolve('Mở Ngôi sao', allowShortDirectCommand: false)
            ?.vocabularyTarget,
        VoiceVocabularyTarget.star,
      );
      expect(
        lexicon.resolve(
          'Tôi nhìn thấy ngôi sao',
          state: ControlledSpeechState.translateContinuous,
        ),
        isNull,
      );
    },
  );
}

class _Context implements ActiveLearningVoiceContext {
  const _Context(this.mainVoiceNode);
  @override
  final ActiveLearningVoiceNode mainVoiceNode;
  @override
  String get mainVoicePrompt => mainVoiceNode == ActiveLearningVoiceNode.song
      ? MasterNavigationContract.songControlPrompt
      : MasterNavigationContract.coreControlPrompt;
}
