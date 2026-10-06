import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_state.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_session_controller.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_controller.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/presentation/main_voice_assistant_button.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'iOS retains numbered Topic choice until route installation succeeds',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final speech = _FakeNavigationSpeechInput();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: _FakeVoicePromptService(),
        mainAssistantFlow: MainVoiceAssistantFlow(
          contentLoader: _loadMainAssistantContent,
        ),
      );
      final acceptedTopics = <int>[];
      controller.setIntentResultHandler((intent) {
        acceptedTopics.add(intent.topicNumber!);
        return acceptedTopics.length > 1;
      });
      expect(
        await controller.activateLevelTopicSelection(
          childAge: 6,
          levelNumber: 1,
          topicNumbers: [1, 2, 3],
          completedTopicNumbers: [],
          announceLevel: false,
        ),
        isTrue,
      );
      expect(await controller.dispatchRecognizedText('Chủ đề số 3'), isFalse);
      expect(acceptedTopics, [3]);
      expect(controller.isAwaitingCommand, isTrue);
      expect(
        controller.mainAssistantStage,
        MainVoiceAssistantStage.chooseTopicAfterCompletion,
      );
      expect(await controller.dispatchRecognizedText('Chủ đề số 3'), isTrue);
      expect(acceptedTopics, [3, 3]);
      expect(controller.mainAssistantStage, MainVoiceAssistantStage.idle);
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  test(
    'Android keeps its navigation handler when iOS result handler exists',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final speech = _FakeNavigationSpeechInput();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: _FakeVoicePromptService(),
        mainAssistantFlow: MainVoiceAssistantFlow(
          contentLoader: _loadMainAssistantContent,
        ),
      );
      var legacyCalls = 0;
      var iosResultCalls = 0;
      controller.setIntentHandler((_) => legacyCalls++);
      controller.setIntentResultHandler((_) {
        iosResultCalls++;
        return false;
      });
      expect(
        await controller.activateLevelTopicSelection(
          childAge: 6,
          levelNumber: 1,
          topicNumbers: [1, 2, 3],
          completedTopicNumbers: [],
          announceLevel: false,
        ),
        isTrue,
      );
      expect(await controller.dispatchRecognizedText('Chủ đề số 3'), isTrue);
      expect(legacyCalls, 1);
      expect(iosResultCalls, 0);
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  test('iOS exposes a terminal Topic microphone failure revision', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final speech = _FakeNavigationSpeechInput();
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: _FakeVoicePromptService(),
      mainAssistantFlow: MainVoiceAssistantFlow(
        contentLoader: _loadMainAssistantContent,
      ),
    );
    expect(
      await controller.activateLevelTopicSelection(
        childAge: 6,
        levelNumber: 1,
        topicNumbers: [1, 2, 3],
        completedTopicNumbers: [],
        announceLevel: false,
      ),
      isTrue,
    );
    final before = controller.iosTopicRecognitionFailureRevision.value;
    // A final recognizer failure is distinct from ordinary silence retries.
    speech.stopFailure = const StreamingSpeechInputException(
      'Không dùng được micro',
      code: 'IOS_FINAL_ERROR',
    );
    speech.emitCompleted();
    await _waitUntil(
      () => controller.iosTopicRecognitionFailureRevision.value > before,
    );
    expect(controller.iosTopicRecognitionFailureRevision.value, before + 1);
    await controller.pause();
    controller.dispose();
    await speech.dispose();
  });

  test(
    'iOS Topic silence signals only after the second command window',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final speech = _FakeNavigationSpeechInput(stopText: '');
      final prompt = _FakeMainTurnVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
        mainAssistantFlow: MainVoiceAssistantFlow(
          contentLoader: _loadMainAssistantContent,
        ),
        commandWindowDuration: const Duration(milliseconds: 100),
        restartDelay: const Duration(milliseconds: 1),
      );
      expect(
        await controller.activateLevelTopicSelection(
          childAge: 6,
          levelNumber: 1,
          topicNumbers: [1, 2, 3],
          completedTopicNumbers: [],
          announceLevel: false,
        ),
        isTrue,
      );
      await _waitUntil(() => prompt.spokenTexts.length >= 2);
      expect(controller.iosTopicRecognitionFailureRevision.value, 0);
      await _waitUntil(() => !controller.isMainButtonSessionActive);
      expect(controller.iosTopicRecognitionFailureRevision.value, 1);
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  test('iOS Topic unrecognized fallback signals only when exhausted', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final speech = _FakeNavigationSpeechInput();
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: _FakeVoicePromptService(),
      mainAssistantFlow: MainVoiceAssistantFlow(
        contentLoader: _loadMainAssistantContent,
      ),
    );
    expect(
      await controller.activateLevelTopicSelection(
        childAge: 6,
        levelNumber: 1,
        topicNumbers: [1, 2, 3],
        completedTopicNumbers: [],
        announceLevel: false,
      ),
      isTrue,
    );
    expect(await controller.dispatchRecognizedText('Không rõ gì hết'), isTrue);
    expect(controller.iosTopicRecognitionFailureRevision.value, 0);
    expect(await controller.dispatchRecognizedText('Không rõ gì hết'), isTrue);
    expect(controller.iosTopicRecognitionFailureRevision.value, 1);
    await controller.pause();
    controller.dispose();
    await speech.dispose();
  });

  test(
    'iOS surfaces an unhandled learning command after native handoff',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final speech = _FakeNavigationSpeechInput();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: _FakeVoicePromptService(),
        activeLearningCommandHandler: (_) async =>
            const ActiveLearningCommandResult.busy(),
      );
      expect(
        await controller.activateFromMainButton(
          activeLearning: true,
          activeLearningKind: ActiveLearningModuleKind.listeningLesson,
        ),
        isTrue,
      );
      expect(await controller.dispatchRecognizedText('Tiếp tục'), isFalse);
      expect(
        controller.lastErrorMessage,
        contains('Chưa thực hiện được lệnh học'),
      );
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  testWidgets('iOS MAIN labels an unhandled command as unfinished', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final speech = _FakeNavigationSpeechInput();
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: _FakeVoicePromptService(),
      activeLearningCommandHandler: (_) async =>
          const ActiveLearningCommandResult.busy(),
    );
    final audioState = _FakeMainAssistantAudioState();
    final speaking = MainSpeakingSessionController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainVoiceAssistantButton(
            voiceController: controller,
            audioState: audioState,
            speakingSessionController: speaking,
            isActivationPending: false,
            onPressed: () async {},
            onLongPressed: () async {},
            onLongPressReleased: () async {},
          ),
        ),
      ),
    );
    expect(
      await controller.activateFromMainButton(
        activeLearning: true,
        activeLearningKind: ActiveLearningModuleKind.listeningLesson,
      ),
      isTrue,
    );
    expect(await controller.dispatchRecognizedText('Tiếp tục'), isFalse);
    await tester.pump();
    expect(find.text('Lệnh chưa xong'), findsOneWidget);
    expect(find.text('Thử lại mic'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    audioState.dispose();
    speaking.dispose();
    await speech.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'cancelled lesson MAIN cannot resume learning after delayed native cleanup',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final speech = _FakeNavigationSpeechInput(stopText: 'Tiếp tục');
      final voice = _DeferredEndMainTurnVoicePromptService();
      final commands = <ActiveLearningCommand>[];
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: voice,
        pauseDrainTimeout: const Duration(milliseconds: 1),
        activeLearningCommandHandler: (command) async {
          commands.add(command);
          return const ActiveLearningCommandResult.handled();
        },
      );
      expect(
        await controller.activateFromMainButton(activeLearning: true),
        isTrue,
      );
      speech.emitCompleted();
      await _waitUntil(
        () => voice.endedReasons.contains('main_assistant_completed'),
      );
      expect(commands, isEmpty);
      // STOP cancels the accepted command while native HFP cleanup is pending.
      await controller.pause();
      expect(
        await controller.activateLevelTopicSelection(
          childAge: 6,
          levelNumber: 1,
          topicNumbers: [1, 2],
          completedTopicNumbers: [],
          announceLevel: false,
        ),
        isTrue,
      );
      voice.pendingEnd.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(commands, isEmpty);
      expect(controller.isListening, isTrue);
      expect(
        controller.mainAssistantStage,
        MainVoiceAssistantStage.chooseTopicAfterCompletion,
      );
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  for (final disposeBeforeReply in [false, true]) {
    test(
      'native MAIN arm reply after cancellation closes its exact turn (dispose=$disposeBeforeReply)',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final speech = _FakeNavigationSpeechInput();
        final voice = _LateBeginMainTurnVoicePromptService();
        final controller = VoiceNavigationController(
          speechInput: speech,
          voicePromptService: voice,
          pauseDrainTimeout: const Duration(seconds: 5),
        );
        final activation = controller.activateFromMainButton();
        await _waitUntil(() => voice.beginCount == 1);
        if (disposeBeforeReply) {
          controller.dispose();
        } else {
          await controller.pause();
        }
        voice.pendingBegin.complete('cancelled-before-timeout');
        expect(await activation, isFalse);
        expect(voice.endedTurnIds, ['cancelled-before-timeout']);
        expect(speech.events, isNot(contains('start')));
        expect(voice.spokenTexts, isEmpty);
        if (!disposeBeforeReply) {
          expect(controller.isMainButtonSessionActive, isFalse);
          expect(controller.isActive, isFalse);
          controller.dispose();
        }
        await speech.dispose();
      },
    );
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'late previous MAIN finalization cannot deactivate a newer Topic choice on $platform',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final speech = _GatedFinalizationSpeechInput();
        final controller = VoiceNavigationController(
          speechInput: speech,
          voicePromptService: _FakeVoicePromptService(),
          mainAssistantFlow: MainVoiceAssistantFlow(
            contentLoader: () async {
              final source = (await _loadMainAssistantContent()).groups.single;
              final sourceTopic = source.topics.single;
              return ListeningContentCatalog(
                groups: [
                  ListeningContentAgeGroup(
                    startAge: source.startAge,
                    endAge: source.endAge,
                    topics: [
                      ListeningTopicContent(
                        id: 'reentry-topic-two',
                        number: 2,
                        titleVi: sourceTopic.titleVi,
                        titleEn: sourceTopic.titleEn,
                        lessons: sourceTopic.lessons,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          pauseDrainTimeout: const Duration(milliseconds: 1),
        );
        final intents = <VoiceNavigationIntent>[];
        controller.setIntentHandler(intents.add);
        Future<bool> activateTopicChoice() =>
            controller.activateLevelTopicSelection(
              childAge: 6,
              levelNumber: 1,
              topicNumbers: [1, 2],
              completedTopicNumbers: [],
              announceLevel: false,
            );
        expect(await activateTopicChoice(), isTrue);
        speech.emitCompleted();
        await _waitUntil(() => speech.pendingStops.length == 1);

        // A fresh MAIN owns another prompt/microphone even when the old Apple
        // Speech finalizer has not replied after the bounded pause drain.
        expect(await activateTopicChoice(), isTrue);
        speech.emitCompleted();
        await _waitUntil(() => speech.pendingStops.length == 2);
        expect(controller.isActive, isTrue);
        speech.completeStop(0, 'Chủ đề 1');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(controller.isActive, isTrue);
        expect(
          controller.mainAssistantStage,
          MainVoiceAssistantStage.chooseTopicAfterCompletion,
        );
        expect(intents, isEmpty);

        speech.completeStop(1, 'Chủ đề 2');
        await _waitUntil(() => intents.isNotEmpty);
        expect(intents.single.topicNumber, 2);
        await controller.pause();
        controller.dispose();
        await speech.dispose();
      },
    );
  }

  test(
    'MAIN item controls remain blocked until native turn cleanup finishes',
    () async {
      final speech = _FakeNavigationSpeechInput(stopText: 'Tiếp tục');
      final prompt = _DeferredEndMainTurnVoicePromptService();
      final commands = <ActiveLearningCommand>[];
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
        activeLearningCommandHandler: (command) async {
          commands.add(command);
          return const ActiveLearningCommandResult.handled();
        },
      );
      expect(
        await controller.activateFromMainButton(
          activeLearning: true,
          activeLearningKind: ActiveLearningModuleKind.listeningLesson,
        ),
        isTrue,
      );
      speech.emitCompleted();
      await _waitUntil(
        () => prompt.endedReasons.contains('main_assistant_completed'),
      );
      expect(controller.isMainButtonSessionActive, isFalse);
      expect(controller.isActive, isTrue);
      expect(commands, isEmpty);
      prompt.pendingEnd.complete();
      await _waitUntil(() => !controller.isActive);
      expect(commands, [ActiveLearningCommand.resume]);
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'Home MAIN keeps numbered topic prefixes and final correction on $platform',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final speech = _FakeNavigationSpeechInput(stopText: 'Chủ đề số ba');
        final prompt = _FakeVoicePromptService();
        final controller = VoiceNavigationController(
          speechInput: speech,
          voicePromptService: prompt,
          mainAssistantFlow: MainVoiceAssistantFlow(
            childAge: 6,
            contentLoader: _loadMainAssistantContent,
          ),
          partialIntentDebounce: const Duration(milliseconds: 1),
        );
        final intents = <VoiceNavigationIntent>[];
        controller.setIntentHandler(intents.add);
        expect(await controller.activateFromMainButton(), isTrue);
        for (final prefix in [
          'Con muốn học chủ đề',
          'Con muốn học chủ đề số',
        ]) {
          speech.emitPartial(prefix);
          if (prefix.endsWith(' số')) speech.emitCommandEndpoint(prefix);
          await Future<void>.delayed(const Duration(milliseconds: 15));
          expect(speech.stopCalls, 0, reason: prefix);
          expect(intents, isEmpty, reason: prefix);
          expect(
            controller.mainAssistantStage,
            MainVoiceAssistantStage.chooseFeature,
          );
        }
        speech.emitPartial('Chủ đề số hai');
        await Future<void>.delayed(const Duration(milliseconds: 15));
        expect(speech.stopCalls, 0);
        speech.emitCommandEndpoint('Chủ đề số hai');
        await _waitUntil(() => intents.isNotEmpty);
        expect(
          intents.single.topicNumber,
          3,
          reason: 'final ASR correction wins',
        );
        expect(prompt.spokenTexts, [MainVoiceAssistantFlow.openingPrompt]);
        await controller.pause();
        controller.dispose();
        await speech.dispose();
      },
    );
  }

  test(
    'topic endpoint validates a complete choice and keeps final correction',
    () async {
      final speech = _FakeNavigationSpeechInput(stopText: 'Chủ đề 3');
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: _FakeVoicePromptService(),
        mainAssistantFlow: MainVoiceAssistantFlow(
          contentLoader: _loadMainAssistantContent,
        ),
        partialIntentDebounce: const Duration(milliseconds: 1),
      );
      final intents = <VoiceNavigationIntent>[];
      controller.setIntentHandler(intents.add);
      await controller.activateLevelTopicSelection(
        childAge: 6,
        levelNumber: 1,
        topicNumbers: [1, 2, 3],
        completedTopicNumbers: [],
        announceLevel: false,
      );

      // "Chủ đề" is a stable ASR prefix of "Chủ đề số 2". It must not be
      // committed as the global OPEN_SUBJECT command while this flow owns the
      // microphone.
      speech.emitPartial('Chủ đề');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(speech.stopCalls, 0);
      expect(intents, isEmpty);
      expect(controller.isListening, isTrue);

      speech.emitPartial('Chủ đề số');
      speech.emitCommandEndpoint('Chủ đề số');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(speech.stopCalls, 0);
      expect(controller.isListening, isTrue);

      // A complete number still waits for end-of-speech or a short silence.
      speech.emitPartial('Chủ đề 2');
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(speech.stopCalls, 0);
      speech.emitCommandEndpoint('Chủ đề 2');
      await _waitUntil(() => intents.isNotEmpty);
      expect(speech.stopCalls, 1);
      expect(
        intents.single.topicNumber,
        3,
        reason: 'final ASR correction wins',
      );
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  test('a complete topic number ends MAIN after a short silence', () async {
    final speech = _FakeNavigationSpeechInput(stopText: 'Chủ đề 3');
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: _FakeVoicePromptService(),
      mainAssistantFlow: MainVoiceAssistantFlow(
        contentLoader: _loadMainAssistantContent,
      ),
      commandSilenceEndpoint: const Duration(milliseconds: 60),
    );
    final intents = <VoiceNavigationIntent>[];
    controller.setIntentHandler(intents.add);
    await controller.activateLevelTopicSelection(
      childAge: 6,
      levelNumber: 1,
      topicNumbers: [1, 2, 3],
      completedTopicNumbers: [],
      announceLevel: false,
    );

    // A pause before the number must not end the turn.
    speech.emitPartial('Chủ đề số');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(speech.stopCalls, 0);
    expect(controller.isListening, isTrue);

    speech.emitPartial('Chủ đề 2');
    await _waitUntil(() => intents.isNotEmpty);
    expect(speech.stopCalls, 1);
    expect(intents.single.topicNumber, 3, reason: 'final ASR correction wins');
    await controller.pause();
    controller.dispose();
    await speech.dispose();
  });

  test('the bare Topics command ends MAIN after a short silence', () async {
    final speech = _FakeNavigationSpeechInput(stopText: 'Chủ đề');
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: _FakeVoicePromptService(),
      mainAssistantFlow: MainVoiceAssistantFlow(
        contentLoader: _loadMainAssistantContent,
      ),
      commandSilenceEndpoint: const Duration(milliseconds: 60),
    );
    final intents = <VoiceNavigationIntent>[];
    controller.setIntentHandler(intents.add);
    await controller.activateFromMainButton();
    await _waitUntil(() => controller.isListening);

    speech.emitPartial('Chủ đề');
    await _waitUntil(() => intents.isNotEmpty);
    expect(speech.stopCalls, 1);
    expect(intents.single.destination, VoiceNavigationDestination.topics);
    expect(intents.single.topicNumber, isNull);
    await controller.pause();
    controller.dispose();
    await speech.dispose();
  });

  test(
    'level silence ends MAIN when a late partial completes the number',
    () async {
      final speech = _FakeNavigationSpeechInput(stopText: 'Chủ đề 3');
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: _FakeVoicePromptService(),
        mainAssistantFlow: MainVoiceAssistantFlow(
          contentLoader: _loadMainAssistantContent,
        ),
        commandSilenceEndpoint: const Duration(milliseconds: 100),
      );
      final intents = <VoiceNavigationIntent>[];
      controller.setIntentHandler(intents.add);
      await controller.activateLevelTopicSelection(
        childAge: 6,
        levelNumber: 1,
        topicNumbers: [1, 2, 3],
        completedTopicNumbers: [],
        announceLevel: false,
      );

      // Room level for calibration, then speech, then silence.
      for (var i = 0; i < 8; i++) {
        speech.emitAmplitude(-58);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      for (var i = 0; i < 6; i++) {
        speech.emitAmplitude(i.isEven ? -22 : -16);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      speech.emitAmplitude(-58);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(speech.stopCalls, 0, reason: 'no complete answer yet');

      // The partial trails the audio; the silence has already elapsed.
      speech.emitPartial('Chủ đề 2');
      await _waitUntil(() => intents.isNotEmpty);
      expect(speech.stopCalls, 1);
      expect(intents.single.topicNumber, 3);
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  test(
    'Android continuous wake emits one cue at command microphone readiness',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final speech = _FakeNavigationSpeechInput();
      final prompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
        restartDelay: const Duration(milliseconds: 1),
        partialIntentDebounce: const Duration(milliseconds: 1),
      );
      controller.startContinuous();
      await _waitUntil(() => controller.isListening);
      expect(prompt.readyCueCount, 0);
      speech.emitPartial('Hey HOMI');
      await _waitUntil(
        () => controller.isAwaitingCommand && controller.isListening,
      );
      expect(prompt.readyCueCount, 1);
      expect(speech.events.where((event) => event == 'start'), hasLength(2));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(prompt.readyCueCount, 1);
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  testWidgets('obsolete start timeout cannot cancel the current mic', (
    tester,
  ) async {
    final speech = _FirstStartBlockedSpeechInput();
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: _FakeMainTurnVoicePromptService(),
      pauseDrainTimeout: const Duration(milliseconds: 1),
      microphoneStartTimeout: const Duration(milliseconds: 100),
    );
    final firstActivation = controller.activateFromMainButton();
    await tester.pump();
    final secondActivation = controller.activateFromMainButton();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2));
    expect(await secondActivation, isTrue);
    final cancellations = speech.events
        .where((event) => event == 'cancel')
        .length;
    await tester.pump(const Duration(milliseconds: 110));
    expect(await firstActivation, isFalse);
    expect(controller.isListening, isTrue);
    expect(controller.lastError, isNull);
    expect(
      speech.events.where((event) => event == 'cancel'),
      hasLength(cancellations),
    );
    speech.firstStart.complete();
    await tester.pump();
    await controller.pause();
    controller.dispose();
    await speech.dispose();
  });

  test('old prompt completion cannot clear a newer MAIN activation', () async {
    final speech = _FakeNavigationSpeechInput();
    final prompt = _FirstPromptBlockedService();
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: prompt,
    );
    final firstActivation = controller.activateFromMainButton();
    await _waitUntil(() => prompt.spokenTexts.isNotEmpty);
    expect(await controller.activateFromMainButton(), isTrue);
    prompt.firstPrompt.complete();
    expect(await firstActivation, isFalse);
    expect(controller.isListening, isTrue);
    expect(controller.isAwaitingCommand, isTrue);
    expect(controller.isMainButtonSessionActive, isTrue);
    expect(controller.continuousRequested, isTrue);
    expect(prompt.endedTurnIds, ['test-main-1']);
    await controller.pause();
    controller.dispose();
    await speech.dispose();
  });

  for (final failLate in [false, true]) {
    test(
      'obsolete microphone start ($failLate) cannot stop the newer MAIN',
      () async {
        final speech = _FirstStartBlockedSpeechInput();
        final controller = VoiceNavigationController(
          speechInput: speech,
          voicePromptService: _FakeMainTurnVoicePromptService(),
          pauseDrainTimeout: const Duration(milliseconds: 1),
        );
        final firstActivation = controller.activateFromMainButton();
        await _waitUntil(() => speech.events.contains('start'));
        expect(await controller.activateFromMainButton(), isTrue);
        final cancellations = speech.events
            .where((event) => event == 'cancel')
            .length;
        if (failLate) {
          speech.firstStart.completeError(
            StateError('obsolete microphone failed'),
          );
        } else {
          speech.firstStart.complete();
        }
        expect(await firstActivation, isFalse);
        expect(controller.isListening, isTrue);
        expect(controller.isAwaitingCommand, isTrue);
        expect(controller.isMainButtonSessionActive, isTrue);
        expect(controller.continuousRequested, isTrue);
        expect(controller.lastError, isNull);
        expect(
          speech.events.where((event) => event == 'cancel'),
          hasLength(cancellations),
        );
        await controller.pause();
        controller.dispose();
        await speech.dispose();
      },
    );
  }

  test(
    'failed MAIN prompt closes its turn without opening microphone',
    () async {
      final speech = _FakeNavigationSpeechInput();
      final prompt = _FailingMainTurnPromptService();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
      );
      expect(await controller.activateFromMainButton(), isFalse);
      expect(speech.events, isNot(contains('start')));
      expect(controller.lastError, isA<StateError>());
      expect(controller.isAwaitingCommand, isFalse);
      expect(controller.continuousRequested, isFalse);
      expect(prompt.endedReasons, ['prompt_failed']);

      // A new deliberate press retries normally instead of leaving MAIN stuck.
      expect(await controller.activateFromMainButton(), isTrue);
      expect(speech.events.where((event) => event == 'start'), hasLength(1));
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  test(
    'failed command acknowledgment does not execute lesson action',
    () async {
      final speech = _FakeNavigationSpeechInput();
      final prompt = _FailingMainTurnPromptService()..failNext = false;
      final commands = <ActiveLearningCommand>[];
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
        activeLearningCommandHandler: (command) async {
          commands.add(command);
          return const ActiveLearningCommandResult.handled();
        },
      );
      expect(
        await controller.activateFromMainButton(activeLearning: true),
        isTrue,
      );
      prompt.failNext = true;
      expect(await controller.dispatchRecognizedText('Nghe lại'), isFalse);
      expect(commands, isEmpty);
      expect(controller.isAwaitingCommand, isFalse);
      expect(controller.continuousRequested, isFalse);
      expect(prompt.endedReasons, ['prompt_failed']);
      controller.dispose();
      await speech.dispose();
    },
  );

  test(
    'failed iOS-style navigation acknowledgment still opens vocabulary',
    () async {
      final speech = _FakeNavigationSpeechInput();
      final prompt = _FailingMainTurnPromptService()..failNext = false;
      final intents = <VoiceNavigationIntent>[];
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
      );
      controller.setIntentHandler(intents.add);

      expect(
        await controller.activateFromMainButton(
          activeLearning: true,
          activeLearningKind: ActiveLearningModuleKind.listeningLesson,
          promptAlreadySpoken: true,
        ),
        isTrue,
      );
      prompt.failNext = true;
      expect(
        await controller.dispatchRecognizedText('Con muốn học từ vựng'),
        isTrue,
      );

      expect(intents, hasLength(1));
      expect(intents.single.destination, VoiceNavigationDestination.vocabulary);
      expect(controller.isMainButtonSessionActive, isFalse);
      expect(prompt.endedReasons, ['prompt_failed']);

      controller.dispose();
      await speech.dispose();
    },
  );

  test(
    'failed iOS-style translation acknowledgment still opens the microphone flow',
    () async {
      final speech = _FakeNavigationSpeechInput();
      final prompt = _FailingMainTurnPromptService()..failNext = false;
      final intents = <VoiceNavigationIntent>[];
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
      );
      controller.setIntentHandler(intents.add);

      expect(
        await controller.activateFromMainButton(promptAlreadySpoken: true),
        isTrue,
      );
      prompt.failNext = true;
      expect(
        await controller.dispatchRecognizedText('Con ghi muốn luyện nói'),
        isTrue,
      );

      expect(intents, hasLength(1));
      expect(
        intents.single.destination,
        VoiceNavigationDestination.conversation,
      );
      expect(intents.single.enterMainSpeakingMode, isTrue);
      expect(controller.isMainButtonSessionActive, isFalse);
      expect(prompt.endedReasons, ['prompt_failed']);

      controller.dispose();
      await speech.dispose();
    },
  );

  test(
    'failed iOS-style start acknowledgment still opens the selected lesson',
    () async {
      final speech = _FakeNavigationSpeechInput();
      final prompt = _FailingMainTurnPromptService()..failNext = false;
      final intents = <VoiceNavigationIntent>[];
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
      );
      controller.setIntentHandler(intents.add);
      final catalog = await _loadMainAssistantContent();
      final topic = catalog.groups.single.topics.single;

      expect(
        await controller.activateLessonSelectionForTopic(
          childAge: 6,
          topicNumber: topic.number,
          topicContent: topic,
          completedLessonNumbers: const <int>[],
        ),
        isTrue,
      );
      prompt.failNext = true;
      expect(await controller.dispatchRecognizedText('Bài 1'), isTrue);

      expect(intents, hasLength(1));
      expect(intents.single.destination, VoiceNavigationDestination.topics);
      expect(intents.single.openLesson, isTrue);
      expect(intents.single.topicNumber, topic.number);
      expect(intents.single.lessonNumber, 1);
      expect(controller.isMainButtonSessionActive, isFalse);
      expect(prompt.endedReasons, ['prompt_failed']);

      controller.dispose();
      await speech.dispose();
    },
  );

  testWidgets('timed-out prompt never becomes a successful question', (
    tester,
  ) async {
    final speech = _FakeNavigationSpeechInput();
    final prompt = _LongAuthoredVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: prompt,
    );
    final activation = controller.activateFromMainButton();
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    expect(await activation, isFalse);
    expect(prompt.stopCalls, 1);
    expect(controller.lastError, isA<TimeoutException>());
    expect(controller.isAwaitingCommand, isFalse);
    expect(speech.events, isNot(contains('start')));
    prompt.complete();
    await tester.pump();
    expect(speech.events, isNot(contains('start')));
    controller.dispose();
    await speech.dispose();
  });

  testWidgets(
    'authored prompt longer than eight seconds finishes before command window opens',
    (tester) async {
      final speechInput = _FakeNavigationSpeechInput();
      final prompt = _LongAuthoredVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: prompt,
      );
      final operation = controller.dispatchRecognizedText('Hey HOMI');
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      expect(controller.isAwaitingCommand, false);
      expect(prompt.stopCalls, 0);
      prompt.complete();
      await tester.pump();
      expect(await operation, true);
      expect(controller.isAwaitingCommand, true);
      controller.dispose();
      await speechInput.dispose();
    },
  );
  test(
    'forced pause stops assistant audio when HOMI leaves foreground',
    () async {
      final speech = _FakeNavigationSpeechInput();
      final prompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
      );

      await controller.pause(stopPrompt: true);

      expect(prompt.stopCalls, 1);
      controller.dispose();
      await speech.dispose();
    },
  );

  test(
    'MAIN-only configuration never starts or acknowledges voice wake',
    () async {
      final speech = _FakeNavigationSpeechInput();
      final prompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
        wakeWordEnabled: false,
      );
      controller.startContinuous();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(speech.events, isEmpty);
      expect(await controller.dispatchRecognizedText('HOMI ơi'), isFalse);
      expect(prompt.spokenTexts, isEmpty);
      expect(await controller.activateFromMainButton(), isTrue);
      expect(prompt.spokenTexts, [MainVoiceAssistantFlow.openingPrompt]);
      controller.dispose();
      await speech.dispose();
    },
  );

  test(
    'two silent active-module windows dispatch STOP rather than resume',
    () async {
      final speech = _FakeNavigationSpeechInput(stopText: '');
      final prompt = _FakeVoicePromptService();
      final commands = <ActiveLearningCommand>[];
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
        commandWindowDuration: const Duration(milliseconds: 25),
        activeLearningCommandHandler: (command) async {
          commands.add(command);
          return const ActiveLearningCommandResult.handled();
        },
      );
      await controller.activateFromMainButton(
        activeLearning: true,
        activeLearningKind: ActiveLearningModuleKind.vocabulary,
        noSpeechRetryPrompt: 'Bạn muốn học nội dung khác hay học lại?',
        noSpeechExitPrompt: 'Mình tạm dừng nhé.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(commands, [ActiveLearningCommand.stop]);
      expect(prompt.spokenTexts.last, 'Mình tạm dừng nhé.');
      expect(controller.isMainButtonSessionActive, isFalse);
      controller.dispose();
      await speech.dispose();
    },
  );

  test('two silent song windows pause the song at its checkpoint', () async {
    final speech = _FakeNavigationSpeechInput(stopText: '');
    final prompt = _FakeVoicePromptService();
    final commands = <ActiveLearningCommand>[];
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: prompt,
      commandWindowDuration: const Duration(milliseconds: 25),
      activeLearningCommandHandler: (command) async {
        commands.add(command);
        return const ActiveLearningCommandResult.handled();
      },
    );
    await controller.activateFromMainButton(
      activeLearning: true,
      activeLearningKind: ActiveLearningModuleKind.listeningLesson,
      activeVoiceContext: const _SongVoiceContext(),
    );

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(commands, <ActiveLearningCommand>[ActiveLearningCommand.stop]);
    expect(prompt.spokenTexts.last, MasterNavigationContract.pause);
    expect(controller.isMainButtonSessionActive, isFalse);
    controller.dispose();
    await speech.dispose();
  });

  test(
    'silent topic selection resumes the same Level when MAIN is pressed again',
    () async {
      final speech = _FakeNavigationSpeechInput();
      final prompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: prompt,
        commandWindowDuration: const Duration(milliseconds: 25),
      );
      await controller.activateLevelTopicSelection(
        childAge: 6,
        levelNumber: 2,
        topicNumbers: [4, 5, 6],
        completedTopicNumbers: [4],
        announceLevel: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(prompt.spokenTexts.last, 'Mình tạm dừng nhé.');
      await controller.activateFromMainButton();
      expect(
        controller.mainAssistantStage,
        MainVoiceAssistantStage.chooseTopicAfterCompletion,
      );
      expect(prompt.spokenTexts.last, 'Có 3 Chủ đề. Bạn chọn Chủ đề số mấy?');
      controller.dispose();
      await speech.dispose();
    },
  );

  test(
    'navigation transcript is handled without entering conversation',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        ownsSpeechInput: true,
      );
      VoiceNavigationIntent? receivedIntent;
      controller.setIntentHandler((intent) {
        receivedIntent = intent;
      });

      expect(
        await controller.dispatchRecognizedText('Con muốn học từ vựng'),
        isFalse,
      );
      expect(receivedIntent, isNull);

      expect(await controller.dispatchRecognizedText('Hey HOMI'), isTrue);
      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.openingPrompt,
      ]);
      expect(voicePrompt.readyCueCount, 0);
      expect(controller.isAwaitingCommand, isTrue);

      expect(
        await controller.dispatchRecognizedText('Con muốn học từ vựng'),
        isTrue,
      );
      expect(
        receivedIntent?.destination,
        VoiceNavigationDestination.vocabulary,
      );

      receivedIntent = null;
      expect(
        await controller.dispatchRecognizedText('Con muốn uống nước'),
        isFalse,
      );
      expect(receivedIntent, isNull);
      controller.dispose();
    },
  );

  test('Main button speaks the menu then starts the speaking flow', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      restartDelay: const Duration(milliseconds: 1),
    );
    VoiceNavigationIntent? receivedIntent;
    controller.setIntentHandler((intent) => receivedIntent = intent);

    expect(
      await controller.activateFromMainButton(
        inputLabelOverride: 'Mic iPhone (giữ BLE HM-D001)',
      ),
      isTrue,
    );
    await Future<void>.delayed(const Duration(milliseconds: 520));

    expect(voicePrompt.spokenTexts, <String>[
      MainVoiceAssistantFlow.openingPrompt,
    ]);
    expect(voicePrompt.readyCueCount, 1);
    expect(controller.isAwaitingCommand, isTrue);
    expect(controller.isListening, isTrue);
    expect(controller.activeInputLabel, 'Mic iPhone (giữ BLE HM-D001)');
    expect(
      await controller.dispatchRecognizedText('Con ghi muốn luyện nói'),
      isTrue,
    );
    expect(voicePrompt.spokenTexts, <String>[
      MainVoiceAssistantFlow.openingPrompt,
      MainVoiceAssistantFlow.continuousTranslationPrompt,
    ]);
    expect(
      receivedIntent?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(receivedIntent?.enterMainSpeakingMode, isTrue);
    expect(controller.continuousRequested, isFalse);

    controller.dispose();
    await speechInput.dispose();
  });

  for (final kind in ActiveLearningModuleKind.values) {
    test(
      'transfer from $kind waits for transition and intro before mic',
      () async {
        final speech = _FakeNavigationSpeechInput();
        final prompt = _TranslationTransferPromptService();
        final controller = VoiceNavigationController(
          speechInput: speech,
          voicePromptService: prompt,
        );
        final intents = <VoiceNavigationIntent>[];
        controller.setIntentHandler(intents.add);
        expect(
          await controller.activateFromMainButton(
            activeLearning: true,
            activeLearningKind: kind,
            promptAlreadySpoken: true,
          ),
          isTrue,
        );
        final microphoneStarts = speech.events
            .where((e) => e == 'start')
            .length;

        final transfer = controller.dispatchRecognizedText('Dịch tiếng Anh');
        await _waitUntil(() => prompt.spokenTexts.isNotEmpty);
        expect(prompt.spokenTexts, [
          MasterNavigationContract.switchedToTranslation,
        ]);
        expect(intents, isEmpty);

        prompt.transition.complete();
        await _waitUntil(() => prompt.spokenTexts.length == 2);
        expect(prompt.spokenTexts, [
          MasterNavigationContract.switchedToTranslation,
          MasterNavigationContract.translationIntro,
        ]);
        expect(intents, isEmpty);
        expect(
          speech.events.where((e) => e == 'start'),
          hasLength(microphoneStarts),
        );

        prompt.intro.complete();
        expect(await transfer, isTrue);
        expect(intents, hasLength(1));
        expect(intents.single.enterMainSpeakingMode, isTrue);
        expect(
          intents.single.destination,
          VoiceNavigationDestination.conversation,
        );
        expect(controller.continuousRequested, isFalse);
        controller.dispose();
        await speech.dispose();
      },
    );
  }

  for (final failIntro in [false, true]) {
    test(
      'cancelled/failed translation intro ($failIntro) has safe terminal handoff',
      () async {
        final speech = _FakeNavigationSpeechInput();
        final prompt = _TranslationTransferPromptService();
        final controller = VoiceNavigationController(
          speechInput: speech,
          voicePromptService: prompt,
        );
        final intents = <VoiceNavigationIntent>[];
        controller.setIntentHandler(intents.add);
        await controller.activateFromMainButton(
          activeLearning: true,
          activeLearningKind: ActiveLearningModuleKind.vocabulary,
          promptAlreadySpoken: true,
        );
        final transfer = controller.dispatchRecognizedText('Dịch tiếng Anh');
        await _waitUntil(() => prompt.spokenTexts.isNotEmpty);
        prompt.transition.complete();
        await _waitUntil(() => prompt.spokenTexts.length == 2);
        if (failIntro) {
          prompt.intro.completeError(StateError('H20 intro playback failed'));
        } else {
          await controller.pause();
          prompt.intro.complete();
        }

        expect(await transfer, failIntro);
        if (failIntro) {
          expect(intents, hasLength(1));
          expect(
            intents.single.destination,
            VoiceNavigationDestination.conversation,
          );
          expect(intents.single.enterMainSpeakingMode, isTrue);
        } else {
          expect(intents, isEmpty);
        }
        expect(controller.continuousRequested, isFalse);
        expect(controller.isListening, isFalse);
        controller.dispose();
        await speech.dispose();
      },
    );
  }

  test(
    'MAIN handles an unambiguous fallback phrase from a stable partial',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        partialIntentDebounce: const Duration(milliseconds: 1),
      );
      VoiceNavigationIntent? receivedIntent;
      controller.setIntentHandler((intent) => receivedIntent = intent);

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => controller.isListening);
      speechInput.emitPartial('Con muốn học từ vựng');
      await _waitUntil(() => receivedIntent != null);

      expect(
        receivedIntent?.destination,
        VoiceNavigationDestination.vocabulary,
      );
      expect(speechInput.events, contains('cancel'));
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test('iOS MAIN prompts use the selected H20 media output', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _SelectedMediaVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
    );
    addTearDown(() async {
      controller.dispose();
      await speechInput.dispose();
    });

    expect(await controller.activateFromMainButton(), isTrue);

    expect(voicePrompt.mediaOutputTexts, <String>[
      MainVoiceAssistantFlow.openingPrompt,
    ]);
    expect(voicePrompt.regularOutputTexts, isEmpty);
  });

  test(
    'iOS MAIN can pin a disconnected virtual turn to the phone mic',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final speechInput = _SourceTrackingNavigationSpeechInput();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: _SelectedMediaVoicePromptService(),
        mainSpeechAudioSource: () => NativeSpeechAudioSource.builtInMic,
      );
      addTearDown(() async {
        controller.dispose();
        await speechInput.dispose();
      });

      expect(await controller.activateFromMainButton(), isTrue);
      await speechInput.startRequested.future;
      expect(speechInput.requestedSources, <NativeSpeechAudioSource>[
        NativeSpeechAudioSource.builtInMic,
      ]);
    },
  );

  test('Android MAIN prompts use the selected H20 HFP output', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _SelectedMediaVoicePromptService();
    var routePreparationCount = 0;
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      prepareSelectedOutput: () async {
        routePreparationCount += 1;
        return true;
      },
    );
    addTearDown(() async {
      controller.dispose();
      await speechInput.dispose();
    });

    expect(await controller.activateFromMainButton(), isTrue);

    expect(voicePrompt.mediaOutputTexts, <String>[
      MainVoiceAssistantFlow.openingPrompt,
    ]);
    expect(routePreparationCount, 1);
    expect(voicePrompt.regularOutputTexts, isEmpty);
  });

  test(
    'Main opens the microphone when the native ready cue never completes',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _HangingReadyCueVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        speechReadyCueTimeout: const Duration(milliseconds: 5),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 520));

      expect(voicePrompt.readyCueCount, 1);
      expect(controller.isAwaitingCommand, isTrue);
      expect(controller.isListening, isTrue);
      expect(
        speechInput.events.where((event) => event == 'start'),
        hasLength(1),
      );

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Main command window starts only after the microphone is ready',
    () async {
      final speechInput = _DelayedNavigationSpeechInput();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: _FakeVoicePromptService(),
        commandWindowDuration: const Duration(milliseconds: 120),
        microphoneStartTimeout: const Duration(seconds: 2),
      );

      final activation = controller.activateFromMainButton();
      await Future<void>.delayed(const Duration(milliseconds: 530));

      expect(controller.isStarting, isTrue);
      expect(controller.isAwaitingCommand, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.isAwaitingCommand, isTrue);

      speechInput.releaseStart();
      await Future<void>.delayed(const Duration(milliseconds: 3));
      expect(await activation, isTrue);
      expect(controller.isListening, isTrue);

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'MAIN final-only completion during native start is finalized once',
    () async {
      final speech = _FirstStartBlockedSpeechInput();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: _FakeVoicePromptService(),
      );

      final activation = controller.activateFromMainButton();
      await _waitUntil(() => speech.events.contains('start'));
      expect(controller.isStarting, isTrue);
      speech.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(speech.stopCalls, 0);

      speech.firstStart.complete();
      expect(await activation, isTrue);
      await _waitUntil(() => speech.stopCalls == 1);
      expect(speech.stopCalls, 1);
      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  test(
    'cancelled early completion cannot finalize a newer MAIN turn',
    () async {
      final speech = _FirstStartBlockedSpeechInput();
      final controller = VoiceNavigationController(
        speechInput: speech,
        voicePromptService: _FakeVoicePromptService(),
        pauseDrainTimeout: const Duration(milliseconds: 1),
      );

      final firstActivation = controller.activateFromMainButton();
      await _waitUntil(() => speech.events.contains('start'));
      speech.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(await controller.activateFromMainButton(), isTrue);
      speech.firstStart.complete();
      expect(await firstActivation, isFalse);
      expect(controller.isListening, isTrue);
      expect(speech.stopCalls, 0);

      await controller.pause();
      controller.dispose();
      await speech.dispose();
    },
  );

  test('actionable topic endpoint during native start is finalized', () async {
    final speech = _FirstStartBlockedSpeechInput();
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: _FakeVoicePromptService(),
    );

    final activation = controller.activateLevelTopicSelection(
      childAge: 6,
      levelNumber: 1,
      topicNumbers: const [1, 2, 3],
      completedTopicNumbers: const [],
      announceLevel: false,
    );
    await _waitUntil(() => speech.events.contains('start'));
    speech.emitCommandEndpoint('Chủ đề 2');
    await Future<void>.delayed(Duration.zero);
    expect(speech.stopCalls, 0);

    speech.firstStart.complete();
    await activation;
    await _waitUntil(() => speech.stopCalls == 1);
    await controller.pause();
    controller.dispose();
    await speech.dispose();
  });

  test('Android MAIN final during ready cue is finalized once', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final speech = _FakeNavigationSpeechInput();
    final prompt = _BlockedReadyCueVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speech,
      voicePromptService: prompt,
    );

    final activation = controller.activateFromMainButton();
    await prompt.cueStarted.future;
    expect(controller.isStarting, isTrue);
    speech.emitCompleted();
    await Future<void>.delayed(Duration.zero);
    expect(speech.stopCalls, 0);

    prompt.releaseCue();
    expect(await activation, isTrue);
    await _waitUntil(() => speech.stopCalls == 1);
    await controller.pause();
    controller.dispose();
    await speech.dispose();
  });

  test(
    'Main prompt reopens the mic immediately after final recognition',
    () async {
      final speechInput = _FakeNavigationSpeechInput(
        stopText: 'Mình chưa biết chọn gì',
      );
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: _FakeVoicePromptService(),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      expect(
        speechInput.events.where((event) => event == 'start'),
        hasLength(1),
      );

      speechInput.emitCompleted();
      await _waitUntil(
        () => speechInput.events.where((event) => event == 'start').length == 2,
        timeout: const Duration(milliseconds: 200),
      );

      expect(controller.isListening, isTrue);
      expect(controller.isAwaitingCommand, isTrue);
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'HFP speech activity extends MAIN command window before transcript',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        commandWindowDuration: const Duration(milliseconds: 250),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => controller.isListening);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      speechInput.emitSpeechStarted();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(controller.isListening, isTrue);
      expect(controller.isAwaitingCommand, isTrue);
      expect(
        voicePrompt.spokenTexts,
        isNot(contains(MainVoiceAssistantFlow.noSpeechRetryPrompt)),
      );

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Main exposes its first microphone start failure without retrying',
    () async {
      final speechInput = _FailingNavigationSpeechInput(failuresRemaining: 1);
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: _FakeVoicePromptService(),
        microphoneStartRetryDelay: const Duration(milliseconds: 2),
      );

      expect(await controller.activateFromMainButton(), isFalse);

      expect(speechInput.startCount, 1);
      expect(controller.isListening, isFalse);
      expect(controller.lastErrorMessage, contains('Không mở được micro'));

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Main pauses its command deadline while a premature completion recovers',
    () async {
      final speechInput = _FakeNavigationSpeechInput(stopText: '');
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        commandWindowDuration: const Duration(milliseconds: 200),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => controller.isListening);
      expect(controller.isListening, isTrue);

      speechInput.emitCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(controller.isMainButtonSessionActive, isTrue);
      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.openingPrompt,
      ]);

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Android MAIN recovers a transient recognizer timeout without showing a mic error',
    () async {
      final speechInput = _TransientFailureNavigationSpeechInput(
        failuresRemaining: 1,
      );
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: _FakeVoicePromptService(),
        commandWindowDuration: const Duration(seconds: 1),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => controller.isListening);

      speechInput.emitCompleted();
      await _waitUntil(
        () => speechInput.events.where((event) => event == 'start').length == 2,
      );

      expect(controller.isListening, isTrue);
      expect(controller.isMainButtonSessionActive, isTrue);
      expect(controller.lastErrorMessage, isNull);

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'repeated Android timeouts use the normal spoken no-speech retry',
    () async {
      final speechInput = _TransientFailureNavigationSpeechInput(
        failuresRemaining: 2,
      );
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        commandWindowDuration: const Duration(seconds: 1),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => controller.isListening);

      speechInput.emitCompleted();
      await _waitUntil(
        () => speechInput.events.where((event) => event == 'start').length == 2,
      );
      speechInput.emitCompleted();
      await _waitUntil(
        () => voicePrompt.spokenTexts.contains(
          MainVoiceAssistantFlow.noSpeechRetryPrompt,
        ),
      );

      expect(controller.lastErrorMessage, isNull);
      expect(controller.isMainButtonSessionActive, isTrue);
      expect(controller.isListening, isTrue);

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'iOS no-speech completion reopens MAIN and uses the spoken silence retry',
    () async {
      final speechInput = _TransientFailureNavigationSpeechInput(
        failuresRemaining: 2,
        failureCode: 'IOS_SPEECH_NO_SPEECH',
      );
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        commandWindowDuration: const Duration(seconds: 1),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => controller.isListening);

      speechInput.emitCompleted();
      await _waitUntil(
        () => speechInput.events.where((event) => event == 'start').length == 2,
      );
      expect(controller.lastErrorMessage, isNull);
      expect(controller.isMainButtonSessionActive, isTrue);

      speechInput.emitCompleted();
      await _waitUntil(
        () => voicePrompt.spokenTexts.contains(
          MainVoiceAssistantFlow.noSpeechRetryPrompt,
        ),
      );
      expect(controller.lastErrorMessage, isNull);
      expect(controller.isListening, isTrue);

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Main stops automatic retries and exposes the microphone error',
    () async {
      final speechInput = _FailingNavigationSpeechInput(failuresRemaining: 10);
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: _FakeVoicePromptService(),
        microphoneStartRetryDelay: const Duration(milliseconds: 2),
      );

      expect(await controller.activateFromMainButton(), isFalse);

      expect(speechInput.startCount, 1);
      expect(controller.isMainButtonSessionActive, isFalse);
      expect(controller.continuousRequested, isFalse);
      expect(controller.lastErrorMessage, contains('Không mở được micro'));

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test('Main activation never exposes a transient inactive session', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: _FakeVoicePromptService(),
    );
    var exposedInactiveSession = false;
    controller.addListener(() {
      if (!controller.isMainButtonSessionActive && !controller.isActive) {
        exposedInactiveSession = true;
      }
    });

    expect(
      await controller.activateFromMainButton(activeLearning: true),
      isTrue,
    );

    expect(exposedInactiveSession, isFalse);
    expect(controller.isMainButtonSessionActive, isTrue);
    controller.dispose();
    await speechInput.dispose();
  });

  test('Main delegates missing profile age to the topic screen', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      mainAssistantFlow: MainVoiceAssistantFlow(
        contentLoader: _loadMainAssistantContent,
      ),
      restartDelay: const Duration(milliseconds: 1),
    );
    final receivedIntents = <VoiceNavigationIntent>[];
    controller.setIntentHandler(receivedIntents.add);

    expect(await controller.activateFromMainButton(), isTrue);
    expect(
      await controller.dispatchRecognizedText('Con muốn học theo chủ đề'),
      isTrue,
    );

    expect(receivedIntents, hasLength(1));
    expect(receivedIntents.single.childAge, isNull);
    expect(receivedIntents.single.topicNumber, isNull);
    expect(
      receivedIntents.single.destination,
      VoiceNavigationDestination.topics,
    );

    expect(voicePrompt.spokenTexts, <String>[
      MainVoiceAssistantFlow.openingPrompt,
    ]);
    expect(controller.isMainButtonSessionActive, isFalse);
    expect(controller.continuousRequested, isFalse);

    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'saved age lets MAIN open Level selection without the legacy total',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        mainAssistantFlow: MainVoiceAssistantFlow(
          contentLoader: _loadMainAssistantContent,
        ),
        restartDelay: const Duration(milliseconds: 1),
      );
      final receivedIntents = <VoiceNavigationIntent>[];
      controller.setIntentHandler(receivedIntents.add);
      controller.setChildAge(6);

      expect(await controller.activateFromMainButton(), isTrue);
      expect(
        await controller.dispatchRecognizedText('Con muốn học theo chủ đề'),
        isTrue,
      );

      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.openingPrompt,
      ]);
      expect(voicePrompt.spokenTexts, isNot(contains('Con mấy tuổi')));
      expect(receivedIntents.single.childAge, 6);
      expect(receivedIntents.single.topicNumber, isNull);
      expect(
        receivedIntents.single.destination,
        VoiceNavigationDestination.topics,
      );
      expect(controller.isMainButtonSessionActive, isFalse);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test('completed topic prompt continues through topic and lesson', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      mainAssistantFlow: MainVoiceAssistantFlow(
        contentLoader: _loadMainAssistantContent,
      ),
      restartDelay: const Duration(milliseconds: 1),
    );
    final receivedIntents = <VoiceNavigationIntent>[];
    controller.setIntentHandler(receivedIntents.add);

    expect(
      await controller.activateLevelTopicSelection(
        childAge: 6,
        levelNumber: 1,
        topicNumbers: const <int>[1, 2, 3],
        completedTopicNumbers: const <int>[3, 5],
        announceLevel: false,
      ),
      isTrue,
    );
    expect(voicePrompt.spokenTexts, <String>[
      'Có 3 Chủ đề. Bạn chọn Chủ đề số mấy?',
    ]);
    expect(controller.isMainButtonSessionActive, isTrue);

    expect(
      await controller.dispatchRecognizedText('Con chọn chủ đề số 3'),
      isTrue,
    );
    expect(receivedIntents, isEmpty);
    expect(
      voicePrompt.spokenTexts.last,
      'Chủ đề 3 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 3?',
    );

    expect(await controller.dispatchRecognizedText('Học lại'), isTrue);
    expect(receivedIntents.single.topicNumber, 3);
    expect(receivedIntents.single.relearnTopic, isTrue);

    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'completed Course Level choice is handled by the MAIN microphone',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        mainAssistantFlow: MainVoiceAssistantFlow(
          contentLoader: _loadMainAssistantContent,
        ),
        restartDelay: const Duration(milliseconds: 1),
      );
      final receivedIntents = <VoiceNavigationIntent>[];
      controller.setIntentHandler(receivedIntents.add);

      expect(
        await controller.activateCourseRelearnLevelSelection(
          childAge: 6,
          levelNumbers: const <int>[1, 2, 3],
        ),
        isTrue,
      );
      expect(
        voicePrompt.spokenTexts.last,
        MainVoiceAssistantFlow.courseRelearnLevelPrompt,
      );

      expect(
        await controller.dispatchRecognizedText('Học lại Level 3'),
        isTrue,
      );
      expect(receivedIntents.single.levelNumber, 3);
      expect(receivedIntents.single.relearnLevel, isTrue);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test('speaking command opens the other-learning voice menu', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      mainAssistantFlow: MainVoiceAssistantFlow(
        vocabularyLoader: () async => const <VocabularyEntry>[],
      ),
      restartDelay: const Duration(milliseconds: 1),
    );
    VoiceNavigationIntent? receivedIntent;
    controller.setIntentHandler((intent) => receivedIntent = intent);

    expect(await controller.activateOtherLearningFromSpeaking(), isTrue);
    expect(voicePrompt.spokenTexts, <String>[
      MainVoiceAssistantFlow.otherLearningPrompt,
    ]);
    expect(controller.isAwaitingCommand, isTrue);

    expect(
      await controller.dispatchRecognizedText('Con muốn học từ vựng'),
      isTrue,
    );
    expect(
      voicePrompt.spokenTexts.last,
      MasterNavigationContract.switchedToVocabulary,
    );
    expect(receivedIntent?.destination, VoiceNavigationDestination.vocabulary);
    expect(controller.isMainButtonSessionActive, isFalse);

    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'two silent translation-switch windows pause without redirecting',
    () async {
      final speechInput = _FakeNavigationSpeechInput(stopText: '');
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        commandWindowDuration: const Duration(milliseconds: 25),
      );
      VoiceNavigationIntent? receivedIntent;
      controller.setIntentHandler((intent) => receivedIntent = intent);

      expect(await controller.activateOtherLearningFromSpeaking(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(voicePrompt.spokenTexts.last, MasterNavigationContract.pause);
      expect(receivedIntent, isNull);
      expect(controller.isMainButtonSessionActive, isFalse);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'translation STOP keeps both menus and mic closed until explicit MAIN',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
      );

      VoiceNavigationIntent? received;
      controller.setIntentHandler((intent) => received = intent);
      await controller.waitForMainAfterTranslationStop();
      controller.startContinuous();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (final text in ['Hey HOMI', 'Tiếp tục dịch', 'Chủ đề']) {
        expect(await controller.dispatchRecognizedText(text), isFalse);
      }
      expect(voicePrompt.spokenTexts, isEmpty);
      expect(speechInput.events.where((event) => event == 'start'), isEmpty);
      expect(controller.isAwaitingCommand, isFalse);
      expect(controller.isListening, isFalse);
      expect(controller.continuousRequested, isFalse);

      expect(await controller.activateFromMainButton(), isTrue);
      expect(voicePrompt.spokenTexts, <String>[
        'Bạn muốn tiếp tục dịch, học Chủ đề hay Bộ từ vựng?',
      ]);
      expect(controller.isAwaitingCommand, isTrue);
      expect(controller.isListening, isTrue);
      expect(
        controller.mainAssistantStage,
        MainVoiceAssistantStage.chooseAfterTranslationStop,
      );

      await controller.dispatchRecognizedText('Dịch');
      expect(voicePrompt.spokenTexts.last, 'Mình tiếp tục nhé.');
      expect(received?.enterMainSpeakingMode, isTrue);
      expect(controller.isMainButtonSessionActive, isFalse);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test('Main opens today practice when parent vocabulary is pending', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final introducedIds = <String>[];
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      mainAssistantFlow: MainVoiceAssistantFlow(
        vocabularyLoader: () async => <VocabularyEntry>[
          VocabularyEntry(
            id: 'parent-cat',
            word: 'Cat',
            meaning: 'Con mèo',
            addedAt: DateTime(2026, 8, 18),
          ),
        ],
        vocabularyIntroducedMarker: (ids) async => introducedIds.addAll(ids),
      ),
    );
    VoiceNavigationIntent? receivedIntent;
    controller.setIntentHandler((intent) => receivedIntent = intent);

    expect(await controller.activateFromMainButton(), isTrue);
    expect(await controller.dispatchRecognizedText('Học từ mới'), isTrue);

    expect(receivedIntent?.destination, VoiceNavigationDestination.vocabulary);
    expect(
      voicePrompt.spokenTexts,
      isNot(contains('Đã có nội dung mới cho bạn. Bắt đầu học thôi!')),
    );
    expect(voicePrompt.spokenTexts, isNot(contains('Cat')));
    expect(introducedIds, isEmpty);
    expect(controller.isMainButtonSessionActive, isFalse);

    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'active lesson Main next answer advances through the module bridge',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeMainTurnVoicePromptService();
      ActiveLearningCommand? receivedCommand;
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        activeLearningCommandHandler: (command) async {
          receivedCommand = command;
          return const ActiveLearningCommandResult.handled();
        },
      );

      expect(
        await controller.activateFromMainButton(activeLearning: true),
        isTrue,
      );
      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.activeLearningPrompt,
      ]);
      expect(await controller.dispatchRecognizedText('Câu tiếp theo'), isTrue);
      expect(
        voicePrompt.spokenTexts.last,
        MasterNavigationContract.nextItemPrompt,
      );
      expect(receivedCommand, ActiveLearningCommand.nextItem);
      expect(controller.isMainButtonSessionActive, isFalse);
      expect(voicePrompt.endedReasons.last, 'main_assistant_completed');
      expect(voicePrompt.endedTurnIds.last, 'test-main-1');

      // The completed command must release the first MAIN turn so the same
      // BLE/screen button can immediately start another one in the lesson.
      expect(
        await controller.activateFromMainButton(activeLearning: true),
        isTrue,
      );
      expect(voicePrompt.beginCount, 2);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Android Core resume speaks HOMI before handing audio to the lesson',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeMainTurnVoicePromptService();
      final promptsAtHandoff = <String>[];
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        activeLearningCommandHandler: (command) async {
          expect(command, ActiveLearningCommand.resume);
          promptsAtHandoff.add(voicePrompt.spokenTexts.last);
          return const ActiveLearningCommandResult.handled();
        },
      );

      expect(
        await controller.activateFromMainButton(
          activeLearning: true,
          activeLearningKind: ActiveLearningModuleKind.listeningLesson,
          activeVoiceContext: const _CoreVoiceContext(),
        ),
        isTrue,
      );
      expect(await controller.dispatchRecognizedText('Tiếp tục'), isTrue);
      expect(promptsAtHandoff, <String>[
        MasterNavigationContract.continueSubject,
      ]);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'iOS lesson MAIN does not stay blocked by a late native turn arm',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _LateBeginMainTurnVoicePromptService();
      ActiveLearningCommand? receivedCommand;
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        pauseDrainTimeout: const Duration(milliseconds: 1),
        activeLearningCommandHandler: (command) async {
          receivedCommand = command;
          return const ActiveLearningCommandResult.handled();
        },
      );

      expect(
        await controller.activateFromMainButton(activeLearning: true),
        isTrue,
      );
      expect(controller.isMainButtonSessionActive, isTrue);

      voicePrompt.pendingBegin.complete('late-ios-main-turn');
      await Future<void>.delayed(Duration.zero);
      expect(await controller.dispatchRecognizedText('Câu tiếp theo'), isTrue);
      expect(receivedCommand, ActiveLearningCommand.nextItem);
      expect(voicePrompt.endedTurnIds.last, 'late-ios-main-turn');

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'active lesson Main previous answer moves back through the module bridge',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeMainTurnVoicePromptService();
      ActiveLearningCommand? receivedCommand;
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        activeLearningCommandHandler: (command) async {
          receivedCommand = command;
          return const ActiveLearningCommandResult.handled();
        },
      );

      expect(
        await controller.activateFromMainButton(activeLearning: true),
        isTrue,
      );
      expect(await controller.dispatchRecognizedText('Nghe câu trước'), isTrue);
      expect(voicePrompt.spokenTexts.last, 'Mình nghe lại câu trước nhé');
      expect(receivedCommand, ActiveLearningCommand.previousItem);
      expect(controller.isMainButtonSessionActive, isFalse);
      expect(voicePrompt.endedReasons.last, 'main_assistant_completed');

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'active lesson Main dispatches the remaining D07 and D08 commands',
    () async {
      const cases = <String, ActiveLearningCommand>{
        'Nghe lại': ActiveLearningCommand.replayCurrent,
        'Học lại từ đầu': ActiveLearningCommand.restart,
        'Bài tiếp theo': ActiveLearningCommand.nextLesson,
      };

      for (final entry in cases.entries) {
        final speechInput = _FakeNavigationSpeechInput();
        final voicePrompt = _FakeVoicePromptService();
        ActiveLearningCommand? receivedCommand;
        final controller = VoiceNavigationController(
          speechInput: speechInput,
          voicePromptService: voicePrompt,
          activeLearningCommandHandler: (command) async {
            receivedCommand = command;
            return const ActiveLearningCommandResult.handled();
          },
        );

        expect(
          await controller.activateFromMainButton(activeLearning: true),
          isTrue,
          reason: entry.key,
        );
        expect(
          await controller.dispatchRecognizedText(entry.key),
          isTrue,
          reason: entry.key,
        );
        expect(receivedCommand, entry.value, reason: entry.key);
        expect(
          controller.isMainButtonSessionActive,
          isFalse,
          reason: entry.key,
        );

        controller.dispose();
        await speechInput.dispose();
      }
    },
  );

  test(
    'active lesson exit choice keeps listening then opens vocabulary',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      ActiveLearningCommand? receivedCommand;
      VoiceNavigationIntent? receivedIntent;
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        activeLearningCommandHandler: (command) async {
          receivedCommand = command;
          return const ActiveLearningCommandResult.handled();
        },
      );
      controller.setIntentHandler((intent) => receivedIntent = intent);

      expect(
        await controller.activateFromMainButton(activeLearning: true),
        isTrue,
      );
      expect(
        await controller.dispatchRecognizedText('Con không muốn học nữa'),
        isTrue,
      );
      expect(
        voicePrompt.spokenTexts.last,
        MainVoiceAssistantFlow.alternativeAfterLearningPrompt,
      );
      expect(controller.isMainButtonSessionActive, isTrue);
      expect(receivedCommand, isNull);

      expect(
        await controller.dispatchRecognizedText('Con muốn học từ vựng'),
        isTrue,
      );
      expect(
        receivedIntent?.destination,
        VoiceNavigationDestination.vocabulary,
      );
      expect(controller.isMainButtonSessionActive, isFalse);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'MAIN finalizes buffered iOS transcript when its command window ends',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      VoiceNavigationIntent? receivedIntent;
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: _FakeVoicePromptService(),
        commandWindowDuration: const Duration(milliseconds: 8),
      );
      controller.setIntentHandler((intent) => receivedIntent = intent);

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => receivedIntent != null);

      expect(
        receivedIntent?.destination,
        VoiceNavigationDestination.vocabulary,
      );
      expect(controller.isMainButtonSessionActive, isFalse);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Main asks once after silence then exits on the second timeout',
    () async {
      final speechInput = _FakeNavigationSpeechInput(stopText: '');
      final voicePrompt = _FakeMainTurnVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        commandWindowDuration: const Duration(milliseconds: 8),
        restartDelay: const Duration(milliseconds: 1),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => voicePrompt.spokenTexts.length >= 2);
      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.openingPrompt,
        MainVoiceAssistantFlow.noSpeechRetryPrompt,
      ]);
      expect(controller.isMainButtonSessionActive, isTrue);

      await _waitUntil(() => voicePrompt.spokenTexts.length >= 3);
      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.openingPrompt,
        MainVoiceAssistantFlow.noSpeechRetryPrompt,
        MainVoiceAssistantFlow.noSpeechExitPrompt,
      ]);
      expect(voicePrompt.readyCueCount, 2);
      expect(controller.isMainButtonSessionActive, isFalse);
      expect(
        voicePrompt.endedReasons,
        contains('main_assistant_no_speech_exit'),
      );

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test('every branch uses the shared second-silence pause prompt', () async {
    final speechInput = _FakeNavigationSpeechInput(stopText: '');
    final voicePrompt = _FakeMainTurnVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      commandWindowDuration: const Duration(milliseconds: 8),
      restartDelay: const Duration(milliseconds: 1),
    );

    expect(
      await controller.activateFromMainButton(
        activeLearning: true,
        activeLearningKind: ActiveLearningModuleKind.vocabulary,
        promptAlreadySpoken: true,
        noSpeechRetryPrompt:
            'Bạn chọn Ngôi sao mới nhất hoặc nghe lại tất cả nhé.',
        noSpeechExitPrompt: 'Mình dừng ở đây nhé.',
      ),
      isTrue,
    );
    await _waitUntil(() => voicePrompt.spokenTexts.length >= 2);

    expect(voicePrompt.spokenTexts, <String>[
      'Bạn chọn Ngôi sao mới nhất hoặc nghe lại tất cả nhé.',
      MainVoiceAssistantFlow.noSpeechExitPrompt,
    ]);

    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'pauses navigation recognizer before conversation can reuse it',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        ownsSpeechInput: true,
      );

      controller.startContinuous();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.isListening, isTrue);

      await controller.pause();
      await speechInput.start();

      expect(speechInput.events, <String>['start', 'cancel', 'start']);
      expect(controller.isActive, isFalse);
      controller.dispose();
    },
  );

  test('handles an explicit command from a stable partial result', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      restartDelay: const Duration(milliseconds: 1),
      partialIntentDebounce: const Duration(milliseconds: 1),
    );
    final receivedIntents = <VoiceNavigationIntent>[];
    controller.setIntentHandler(receivedIntents.add);

    controller.startContinuous();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    speechInput.emitPartial('Hey HOMI');
    await Future<void>.delayed(const Duration(milliseconds: 140));
    expect(voicePrompt.spokenTexts, <String>[
      MainVoiceAssistantFlow.openingPrompt,
    ]);
    expect(controller.isAwaitingCommand, isTrue);
    expect(controller.isListening, isTrue);

    speechInput.emitPartial('Con muon');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(receivedIntents, isEmpty);

    speechInput.emitPartial('Con muon hoc tu vung');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(receivedIntents, hasLength(1));
    expect(
      speechInput.events.where((event) => event == 'cancel'),
      hasLength(2),
    );
    speechInput.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(receivedIntents, hasLength(1));
    expect(
      receivedIntents.single.destination,
      VoiceNavigationDestination.vocabulary,
    );
    controller.dispose();
    await speechInput.dispose();
  });

  test('hears the wake phrase from a secondary Android transcript', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      restartDelay: const Duration(milliseconds: 1),
      partialIntentDebounce: const Duration(milliseconds: 1),
    );

    controller.startContinuous();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    speechInput.emitAlternatives(<String>['Thời tiết hôm nay', 'Hay HO MIE']);
    await Future<void>.delayed(const Duration(milliseconds: 140));

    expect(voicePrompt.spokenTexts, <String>[
      MainVoiceAssistantFlow.openingPrompt,
    ]);
    expect(controller.isAwaitingCommand, isTrue);
    await controller.pause();
    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'uses final Android alternatives when the primary text misses',
    () async {
      final speechInput = _FakeNavigationSpeechInput(
        stopText: 'Thời tiết hôm nay',
        stopAlternatives: const <String>['Thời tiết hôm nay', 'Hey HOMI'],
      );
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        restartDelay: const Duration(milliseconds: 1),
      );

      controller.startContinuous();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      speechInput.emitCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.openingPrompt,
      ]);
      expect(controller.isAwaitingCommand, isTrue);
      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test('wake-word MAIN exits after its two silent command windows', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: _FakeVoicePromptService(),
      commandWindowDuration: const Duration(milliseconds: 30),
      partialIntentDebounce: const Duration(milliseconds: 1),
    );

    controller.startContinuous();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    speechInput.emitPartial('Hey HOMI');
    await Future<void>.delayed(const Duration(milliseconds: 115));
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(controller.isAwaitingCommand, isFalse);
    expect(
      await controller.dispatchRecognizedText('Con muon hoc tu vung'),
      isFalse,
    );
    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'does not reopen the microphone until the wake reply finishes',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _BlockingVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        partialIntentDebounce: const Duration(milliseconds: 1),
      );

      controller.startContinuous();
      await _waitUntil(() => controller.isListening);
      speechInput.emitPartial('Hey HOMI');
      await _waitUntil(() => controller.isAcknowledgingWakeWord);

      expect(controller.isAcknowledgingWakeWord, isTrue);
      expect(controller.isListening, isFalse);
      expect(
        speechInput.events.where((event) => event == 'start'),
        hasLength(1),
      );

      voicePrompt.complete();
      await _waitUntil(() => controller.isListening);

      expect(controller.isAcknowledgingWakeWord, isFalse);
      expect(controller.isAwaitingCommand, isTrue);
      expect(controller.isListening, isTrue);
      expect(
        speechInput.diagnosticStages,
        containsAllInOrder(<String>[
          'prompt_done',
          'microphone_start_requested',
          'microphone_listening',
        ]),
      );
      expect(
        speechInput.events.where((event) => event == 'start'),
        hasLength(2),
      );
      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'pause waits for a pending navigation start to release the mic',
    () async {
      final speechInput = _DelayedNavigationSpeechInput();
      final controller = VoiceNavigationController(speechInput: speechInput);

      controller.startContinuous();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.isStarting, isTrue);

      var pauseCompleted = false;
      final pauseFuture = controller.pause().then((_) => pauseCompleted = true);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(pauseCompleted, isFalse);

      speechInput.releaseStart();
      await pauseFuture;
      await speechInput.start();
      await Future<void>.delayed(const Duration(milliseconds: 2));

      expect(speechInput.events, <String>[
        'start.begin',
        'cancel',
        'start.end',
        'cancel',
        'start.begin',
        'start.end',
      ]);
      expect(controller.isActive, isFalse);
      controller.dispose();
      await speechInput.dispose();
    },
  );

  testWidgets(
    'screen MAIN interrupts continuous translation during recording and playback',
    (tester) async {
      final speechInput = _FakeNavigationSpeechInput();
      final voiceController = VoiceNavigationController(
        speechInput: speechInput,
      );
      final speakingController = MainSpeakingSessionController();
      final audioState = _FakeMainAssistantAudioState();
      var mainPresses = 0;

      speakingController.enter();
      audioState.isBusy = true;
      speakingController.synchronize(
        isRecording: true,
        isBusy: true,
        isPlaying: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MainVoiceAssistantButton(
              voiceController: voiceController,
              audioState: audioState,
              speakingSessionController: speakingController,
              isActivationPending: false,
              onPressed: () async {
                mainPresses += 1;
              },
              onLongPressed: () async {},
              onLongPressReleased: () async {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('main-voice-assistant-button')));
      await tester.pump();
      expect(mainPresses, 1);

      audioState.isBusy = false;
      audioState.isPlaybackPlaying = true;
      speakingController.synchronize(
        isRecording: false,
        isBusy: false,
        isPlaying: true,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('main-voice-assistant-button')));
      await tester.pump();
      expect(mainPresses, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      speakingController.dispose();
      voiceController.dispose();
      audioState.dispose();
      await speechInput.dispose();
    },
  );
}

class _FakeMainAssistantAudioState extends ChangeNotifier
    implements MainAssistantAudioState {
  @override
  bool isBusy = false;

  @override
  bool isPlaybackPlaying = false;

  @override
  bool isPreparingMicrophone = false;
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the expected navigation state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<ListeningContentCatalog> _loadMainAssistantContent() async {
  return const ListeningContentCatalog(
    groups: <ListeningContentAgeGroup>[
      ListeningContentAgeGroup(
        startAge: 6,
        endAge: 7,
        topics: <ListeningTopicContent>[
          ListeningTopicContent(
            id: 'a067_t03',
            number: 3,
            titleVi: 'Cặp sách và lớp học',
            titleEn: 'School Bag and Classroom',
            lessons: <ListeningLessonContent>[
              ListeningLessonContent(
                id: 'lesson-1',
                number: 1,
                titleVi: 'Đồ dùng học tập',
                titleEn: 'School Supplies',
                intro: '',
                outro: '',
                estimatedMinutes: 3,
                sentences: <ListeningSentenceContent>[],
              ),
              ListeningLessonContent(
                id: 'lesson-2',
                number: 2,
                titleVi: 'Trong lớp học',
                titleEn: 'In the Classroom',
                intro: '',
                outro: '',
                estimatedMinutes: 3,
                sentences: <ListeningSentenceContent>[],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _SourceTrackingNavigationSpeechInput extends _FakeNavigationSpeechInput
    implements NativeSpeechAudioSourceControl {
  final requestedSources = <NativeSpeechAudioSource>[];
  final startRequested = Completer<void>();

  @override
  void useNativeSpeechAudioSourceOnce(NativeSpeechAudioSource source) {
    requestedSources.add(source);
  }

  @override
  Future<void> start() async {
    if (!startRequested.isCompleted) startRequested.complete();
    await super.start();
  }
}

class _FakeNavigationSpeechInput
    implements
        StreamingSpeechInput,
        SpeechActivityStreamingSpeechInput,
        CommandSpeechEndpointInput,
        AlternativeTranscriptStreamingSpeechInput,
        NativeSpeechDiagnostics {
  _FakeNavigationSpeechInput({
    this.stopText = 'Con muốn học từ vựng',
    this.stopAlternatives = const <String>[],
  });

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _speechStartedController =
      StreamController<void>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();
  final StreamController<String> _commandEndpointController =
      StreamController<String>.broadcast();
  final StreamController<List<String>> _alternativeTextController =
      StreamController<List<String>>.broadcast();
  final StreamController<NativeSpeechDiagnostic> _diagnosticsController =
      StreamController<NativeSpeechDiagnostic>.broadcast();
  final List<String> events = <String>[];
  final List<String> diagnosticStages = <String>[];
  int stopCalls = 0;
  Object? stopFailure;
  final String stopText;
  final List<String> stopAlternatives;
  NativeSpeechDiagnostic? _nativeDiagnostic;

  void emitPartial(String text) => _partialTextController.add(text);
  void emitAmplitude(double dbfs) => _amplitudeController.add(dbfs);
  void emitCommandEndpoint(String text) => _commandEndpointController.add(text);

  void emitAlternatives(List<String> alternatives) =>
      _alternativeTextController.add(alternatives);

  void emitCompleted() => _completedController.add(null);

  void emitSpeechStarted() => _speechStartedController.add(null);

  @override
  String get label => 'Navigation ASR';

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get speechStarted => _speechStartedController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Stream<String> get commandSpeechEnded => _commandEndpointController.stream;

  @override
  Stream<List<String>> get transcriptAlternatives =>
      _alternativeTextController.stream;

  @override
  NativeSpeechDiagnostic? get nativeSpeechDiagnostic => _nativeDiagnostic;

  @override
  Stream<NativeSpeechDiagnostic> get nativeSpeechDiagnostics =>
      _diagnosticsController.stream;

  @override
  void reportNativeSpeechStage(
    String stage, {
    String? audioSource,
    String? audioRoute,
    String? code,
    String? message,
    String? turnId,
    int? sequence,
    int? elapsedMs,
    String? caller,
    DateTime? occurredAt,
  }) {
    diagnosticStages.add(stage);
    _nativeDiagnostic = NativeSpeechDiagnostic(
      stage: stage,
      occurredAt: occurredAt ?? DateTime.now(),
      audioSource: audioSource,
      audioRoute: audioRoute,
      code: code,
      message: message,
      turnId: turnId,
      sequence: sequence,
      elapsedMs: elapsedMs,
      caller: caller,
    );
    _diagnosticsController.add(_nativeDiagnostic!);
  }

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {
    events.add('start');
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    stopCalls++;
    if (stopFailure case final failure?) throw failure;
    return StreamingSpeechCapture(
      sourceText: stopText,
      duration: const Duration(seconds: 1),
      inputLabel: 'Navigation ASR',
      confidence: 0.9,
      firstResultMs: 100,
      finalAfterStopMs: 20,
      alternatives: stopAlternatives,
    );
  }

  @override
  Future<void> cancel() async {
    events.add('cancel');
  }

  @override
  Future<void> dispose() async {
    await _amplitudeController.close();
    await _speechStartedController.close();
    await _completedController.close();
    await _partialTextController.close();
    await _commandEndpointController.close();
    await _alternativeTextController.close();
    await _diagnosticsController.close();
  }
}

class _GatedFinalizationSpeechInput extends _FakeNavigationSpeechInput {
  final pendingStops = <Completer<StreamingSpeechCapture>>[];

  @override
  Future<StreamingSpeechCapture> stop() {
    stopCalls++;
    final pending = Completer<StreamingSpeechCapture>();
    pendingStops.add(pending);
    return pending.future;
  }

  void completeStop(int index, String text) {
    pendingStops[index].complete(
      StreamingSpeechCapture(
        sourceText: text,
        duration: const Duration(seconds: 1),
        inputLabel: label,
        confidence: 0.9,
        firstResultMs: 100,
        finalAfterStopMs: 20,
      ),
    );
  }
}

class _SongVoiceContext implements ActiveLearningVoiceContext {
  const _SongVoiceContext();

  @override
  ActiveLearningVoiceNode get mainVoiceNode => ActiveLearningVoiceNode.song;

  @override
  String get mainVoicePrompt => MasterNavigationContract.songControlPrompt;
}

class _CoreVoiceContext implements ActiveLearningVoiceContext {
  const _CoreVoiceContext();

  @override
  ActiveLearningVoiceNode get mainVoiceNode => ActiveLearningVoiceNode.core;

  @override
  String get mainVoicePrompt => MasterNavigationContract.coreControlPrompt;
}

class _TransientFailureNavigationSpeechInput
    extends _FakeNavigationSpeechInput {
  _TransientFailureNavigationSpeechInput({
    required this.failuresRemaining,
    this.failureCode = 'ANDROID_SPEECH_6',
  });

  int failuresRemaining;
  final String failureCode;

  @override
  Future<StreamingSpeechCapture> stop() async {
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw StreamingSpeechInputException(
        'Chưa nghe thấy giọng nói.',
        code: failureCode,
      );
    }
    return super.stop();
  }
}

class _FakeVoicePromptService
    implements VoicePromptService, SpeechReadyCuePlayer {
  final List<String> spokenTexts = <String>[];
  final List<String> spokenLocales = <String>[];
  int readyCueCount = 0;
  int stopCalls = 0;

  @override
  Future<void> playSpeechReadyCue() async {
    readyCueCount += 1;
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spokenTexts.add(text);
    spokenLocales.add(locale);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeMainTurnVoicePromptService extends _FakeVoicePromptService
    implements MainTurnVoicePromptService {
  int beginCount = 0;
  final List<String> endedReasons = <String>[];
  final List<String?> endedTurnIds = <String?>[];

  @override
  Future<String?> beginMainTurn() async {
    beginCount += 1;
    return 'test-main-$beginCount';
  }

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    endedReasons.add(reason);
    endedTurnIds.add(turnId);
  }
}

class _DeferredEndMainTurnVoicePromptService
    extends _FakeMainTurnVoicePromptService {
  final pendingEnd = Completer<void>();

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    await super.endMainTurn(reason, turnId: turnId);
    if (reason == 'main_assistant_completed') await pendingEnd.future;
  }
}

class _LateBeginMainTurnVoicePromptService
    extends _FakeMainTurnVoicePromptService {
  final Completer<String?> pendingBegin = Completer<String?>();

  @override
  Future<String?> beginMainTurn() {
    beginCount += 1;
    return pendingBegin.future;
  }
}

class _FirstPromptBlockedService extends _FakeMainTurnVoicePromptService {
  final firstPrompt = Completer<void>();

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    await super.speakAndWait(text, locale: locale);
    if (spokenTexts.length == 1) await firstPrompt.future;
  }
}

class _TranslationTransferPromptService
    extends _FakeMainTurnVoicePromptService {
  final transition = Completer<void>();
  final intro = Completer<void>();

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    await super.speakAndWait(text, locale: locale);
    if (text == MasterNavigationContract.switchedToTranslation) {
      await transition.future;
    } else if (text == MasterNavigationContract.translationIntro) {
      await intro.future;
    }
  }
}

class _FirstStartBlockedSpeechInput extends _FakeNavigationSpeechInput {
  final firstStart = Completer<void>();

  @override
  Future<void> start() async {
    await super.start();
    if (events.where((event) => event == 'start').length == 1) {
      await firstStart.future;
    }
  }
}

class _FailingMainTurnPromptService extends _FakeMainTurnVoicePromptService {
  bool failNext = true;

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    if (failNext) {
      failNext = false;
      throw StateError('H20 prompt route lost');
    }
    await super.speakAndWait(text, locale: locale);
  }
}

class _SelectedMediaVoicePromptService extends _FakeVoicePromptService
    implements SelectedMediaOutputVoicePromptService {
  final List<String> mediaOutputTexts = <String>[];
  final List<String> regularOutputTexts = <String>[];

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    regularOutputTexts.add(text);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    regularOutputTexts.add(text);
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) async {
    mediaOutputTexts.add(text);
  }
}

class _BlockingVoicePromptService extends _FakeVoicePromptService {
  final Completer<void> _completion = Completer<void>();

  void complete() => _completion.complete();

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    await super.speak(text, locale: locale);
    await _completion.future;
  }
}

class _LongAuthoredVoicePromptService extends _BlockingVoicePromptService
    implements AuthoredPromptBudgetProvider {
  @override
  Future<Duration?> authoredPromptBudget(
    String text, {
    String locale = 'vi-VN',
  }) async => const Duration(seconds: 20);
  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

class _HangingReadyCueVoicePromptService extends _FakeVoicePromptService {
  final Completer<void> _neverCompletes = Completer<void>();

  @override
  Future<void> playSpeechReadyCue() {
    readyCueCount += 1;
    return _neverCompletes.future;
  }
}

class _BlockedReadyCueVoicePromptService extends _FakeVoicePromptService {
  final Completer<void> cueStarted = Completer<void>();
  final Completer<void> _cueFinished = Completer<void>();

  void releaseCue() => _cueFinished.complete();

  @override
  Future<void> playSpeechReadyCue() async {
    readyCueCount += 1;
    if (!cueStarted.isCompleted) cueStarted.complete();
    await _cueFinished.future;
  }
}

class _DelayedNavigationSpeechInput implements StreamingSpeechInput {
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();
  final Completer<void> _firstStartGate = Completer<void>();
  final List<String> events = <String>[];
  var _startCount = 0;

  void releaseStart() => _firstStartGate.complete();

  @override
  String get label => 'Delayed navigation ASR';

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {
    _startCount += 1;
    events.add('start.begin');
    if (_startCount == 1) {
      await _firstStartGate.future;
    }
    events.add('start.end');
  }

  @override
  Future<StreamingSpeechCapture> stop() {
    throw UnimplementedError();
  }

  @override
  Future<void> cancel() async {
    events.add('cancel');
  }

  @override
  Future<void> dispose() async {
    await _amplitudeController.close();
    await _completedController.close();
    await _partialTextController.close();
  }
}

class _FailingNavigationSpeechInput extends _FakeNavigationSpeechInput {
  _FailingNavigationSpeechInput({required this.failuresRemaining});

  int failuresRemaining;
  int startCount = 0;

  @override
  Future<void> start() async {
    startCount += 1;
    events.add('start');
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const StreamingSpeechInputException(
        'Không mở được micro thử nghiệm.',
        code: 'TEST_MICROPHONE_START_FAILED',
      );
    }
  }
}
