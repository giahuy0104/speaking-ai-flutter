import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_gain.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_challenge_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final cancel in <bool>[false, true]) {
    testWidgets(
      'Android Challenge waits for ready cue${cancel ? " and MAIN cancels pending capture" : " before recording"}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await _usePhoneSurface(tester);
        final registry = ActiveLearningModuleRegistry();
        addTearDown(registry.dispose);
        final media = _FakeLessonMediaService();
        final prompts = _GatedChallengeCuePrompt();
        await tester.pumpWidget(
          ActiveLearningModuleScope(
            registry: registry,
            child: _subject(
              startAge: 7,
              mediaService: media,
              voicePromptService: prompts,
            ),
          ),
        );
        await _pumpChallengeTransition(tester);
        expect(prompts.cueStarted, isTrue);
        expect(media.recordingStarts, 0);
        expect(media.selectedOutputPreparations, 2);
        if (cancel) await registry.pauseForMainAssistant();
        prompts.cue.complete();
        await _pumpChallengeTransition(tester);
        expect(media.recordingStarts, cancel ? 0 : 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('failed Challenge retry prompt cannot reopen capture', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final media = _FakeLessonMediaService();
    final prompts = _FailingRetryQuestionPrompt();
    await tester.pumpWidget(
      _subject(
        startAge: 7,
        mediaService: media,
        voicePromptService: prompts,
        attemptEvaluator: _QueuedAttemptEvaluator(<LessonAttemptOutcome>[
          LessonAttemptOutcome.retry,
        ]),
      ),
    );
    await _pumpChallengeTransition(tester);
    expect(media.recordingStarts, 1);
    await tester.tap(find.byKey(const Key('lesson-challenge-record-button')));
    await _pumpChallengeTransition(tester);
    expect(prompts.questionCalls, 2);
    expect(media.recordingStarts, 1);
    expect(
      find.text('Chưa phát được câu hỏi. Bạn bấm nghe lại nhé.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'MAIN during old Challenge feedback cannot advance the resumed question',
    (tester) async {
      await _usePhoneSurface(tester);
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final media = _FakeLessonMediaService();
      final prompts = _GatedChallengeFeedbackPrompt();
      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: _subject(
            startAge: 7,
            mediaService: media,
            voicePromptService: prompts,
          ),
        ),
      );
      await _pumpChallengeTransition(tester);
      await tester.tap(find.byKey(const Key('lesson-challenge-record-button')));
      await _pumpChallengeTransition(tester);
      expect(prompts.feedbackStarted, isTrue);
      await registry.pauseForMainAssistant();
      await registry.execute(ActiveLearningCommand.replayCurrent);
      await _pumpChallengeTransition(tester);
      final starts = media.recordingStarts;
      prompts.feedback.complete();
      await _pumpChallengeTransition(tester);
      expect(media.recordingStarts, starts);
      expect(find.byType(LessonChallengeScreen), findsOneWidget);
      expect(find.text('Dừng và chấm'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets('failed Challenge question does not open mic', (tester) async {
    await _usePhoneSurface(tester);
    final media = _FakeLessonMediaService();
    await tester.pumpWidget(
      _subject(
        startAge: 7,
        mediaService: media,
        voicePromptService: _FailingVoicePromptService(),
      ),
    );
    await _pumpChallengeTransition(tester);
    expect(media.recordingStarts, 0);
    expect(
      find.text('Chưa phát được câu hỏi. Bạn bấm nghe lại nhé.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyed challenge uses manifest budget before opening mic', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final media = _FakeLessonMediaService();
    final prompts = _KeyedChallengeVoicePromptService(gateQuestion: true);
    await tester.pumpWidget(
      _subject(startAge: 7, mediaService: media, voicePromptService: prompts),
    );
    await tester.pump();
    await tester.pump();

    expect(prompts.audioKeys, <String>[
      'listening.challenge.challenge-1.prompt.vi',
    ]);
    expect(prompts.budgetKeys, prompts.audioKeys);
    expect(media.recordingStarts, 0);

    await tester.pump(const Duration(seconds: 11));
    expect(media.recordingStarts, 0);
    prompts.questionGate.complete();
    await _pumpChallengeTransition(tester);
    expect(media.recordingStarts, 1);
  });

  testWidgets('correct challenge uses shared keyed feedback and completion', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final media = _FakeLessonMediaService();
    final prompts = _KeyedChallengeVoicePromptService();
    await tester.pumpWidget(
      _subject(startAge: 7, mediaService: media, voicePromptService: prompts),
    );
    await _pumpChallengeTransition(tester);
    await tester.tap(find.byKey(const Key('lesson-challenge-record-button')));
    await _pumpChallengeTransition(tester);

    expect(
      prompts.audioKeys,
      containsAllInOrder(<String>[
        'listening.challenge.challenge-1.prompt.vi',
        'listening.feedback.correct.vi',
        'listening.feedback.completed.vi',
      ]),
    );
  });
  testWidgets('Challenge resume uses only RESUME_CHALLENGE before replay', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final voicePrompt = _RecordingVoicePromptService();
    final mediaService = _FakeLessonMediaService();

    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: _subject(
          startAge: 7,
          voicePromptService: voicePrompt,
          mediaService: mediaService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    voicePrompt.spoken.clear();

    expect(await registry.pauseForMainAssistant(), isTrue);
    expect(
      (await registry.execute(ActiveLearningCommand.resume)).wasHandled,
      isTrue,
    );
    await tester.pump();
    await tester.pump();

    expect(
      voicePrompt.spoken,
      containsAllInOrder(<String>[
        'vi-VN|Mình tiếp tục câu thử thách nhé.',
        'vi-VN|Where is the library?',
        'vi-VN|Bạn trả lời nhé',
      ]),
    );
    expect(
      voicePrompt.spoken.where((item) => item.contains('Cùng học tiếp')),
      isEmpty,
    );
    expect(mediaService.recordingStarts, 2);
  });

  testWidgets('long authored challenge finishes before the microphone opens', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final media = _FakeLessonMediaService();
    final voice = _LongAuthoredChallengePrompt();
    await tester.pumpWidget(
      _subject(startAge: 7, mediaService: media, voicePromptService: voice),
    );
    await _pumpChallengeTransition(tester);
    await tester.pump(const Duration(seconds: 11));
    expect(voice.stopCalls, 0);
    expect(media.recordingStarts, 0);
    voice.completion.complete();
    await _pumpChallengeTransition(tester);
    expect(media.recordingStarts, 1);
  });

  testWidgets(
    'ignores legacy role-play data and keeps the authored Challenge choices',
    (tester) async {
      await _usePhoneSurface(tester);

      await tester.pumpWidget(_subject(startAge: 8));
      await tester.pump();
      await tester.pump();

      expect(find.text('Đoạn hội thoại'), findsNothing);
      expect(find.text('Thử thách nghe'), findsOneWidget);
      expect(find.byKey(const Key('virtual-lesson-controls')), findsNothing);
      expect(find.text('Nghe và trả lời'), findsOneWidget);
      expect(find.text('Where is the library?'), findsOneWidget);
      expect(find.text('Go straight.'), findsOneWidget);
      expect(find.text('It is five dollars.'), findsOneWidget);
      expect(
        find.text('Hãy nói đáp án bằng tiếng Anh, không nói A hoặc B.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('lesson-challenge-record-button')),
        findsOneWidget,
      );
      expect(find.text('Dừng và chấm'), findsOneWidget);
    },
  );

  testWidgets('multiple legacy inputs never award Challenge Stars', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _FakeLessonMediaService();
    final earnedStars = <String>[];
    await tester.pumpWidget(
      _subject(
        startAge: 7,
        mediaService: mediaService,
        onStarEarned: (targetId, _, _) async => earnedStars.add(targetId),
        challenges: const <ListeningChallengeContent>[
          ListeningChallengeContent(
            id: 'challenge-1',
            format: 'VI_TO_EN',
            prompt: 'Where is the library?',
            choices: <String>['Go straight.', 'It is five dollars.'],
            correctAnswer: 'Go straight.',
            correctVietnamese: 'Đi thẳng.',
            targetId: 'target-1',
          ),
          ListeningChallengeContent(
            id: 'challenge-2',
            format: 'VI_TO_EN',
            prompt: 'How are you?',
            choices: <String>['I am fine.', 'I am eight.'],
            correctAnswer: 'I am fine.',
            correctVietnamese: 'Con khỏe.',
            targetId: 'target-2',
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(mediaService.selectedOutputPreparations, 1);
    expect(mediaService.recordingStarts, 1);
    expect(find.text('Dừng và chấm'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lesson-challenge-record-button')));
    await _pumpChallengeTransition(tester);

    expect(find.text('Câu 2/2'), findsOneWidget);
    // Correct feedback is spoken before the second authored question.
    expect(mediaService.selectedOutputPreparations, 3);
    expect(mediaService.recordingStarts, 2);
    expect(earnedStars, isEmpty);
    expect(find.text('Dừng và chấm'), findsOneWidget);
  });

  testWidgets('Challenge has no Skip action', (tester) async {
    await _usePhoneSurface(tester);
    await tester.pumpWidget(_subject(startAge: 7));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('lesson-challenge-skip-button')), findsNothing);
    expect(find.textContaining('Bỏ qua'), findsNothing);
  });

  testWidgets(
    'opens the H20 microphone when iOS TTS omits its finish callback',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _usePhoneSurface(tester);
      final mediaService = _FakeLessonMediaService();
      final voicePromptService = _MissingSecondFinishVoicePromptService();
      await tester.pumpWidget(
        _subject(
          startAge: 7,
          mediaService: mediaService,
          voicePromptService: voicePromptService,
        ),
      );
      await tester.pump();

      expect(mediaService.recordingStarts, 0);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(voicePromptService.stopCalls, greaterThanOrEqualTo(1));
      expect(mediaService.recordingStarts, 1);
      expect(find.text('Dừng và chấm'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('iOS silent question timeout stops without opening mic', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _usePhoneSurface(tester);
    final media = _FakeLessonMediaService();
    final prompt = _MissingFirstFinishVoicePromptService();
    await tester.pumpWidget(
      _subject(startAge: 7, mediaService: media, voicePromptService: prompt),
    );
    await _pumpChallengeTransition(tester);
    await tester.pump(const Duration(seconds: 10));
    await _pumpChallengeTransition(tester);

    expect(prompt.stopCalls, 1);
    expect(media.recordingStarts, 0);
    expect(
      find.text('Chưa phát được câu hỏi. Bạn bấm nghe lại nhé.'),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android prompt timeout stops speech without opening mic', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _usePhoneSurface(tester);
    final media = _FakeLessonMediaService();
    final prompt = _MissingSecondFinishVoicePromptService();
    await tester.pumpWidget(
      _subject(startAge: 7, mediaService: media, voicePromptService: prompt),
    );
    await _pumpChallengeTransition(tester);
    await tester.pump(const Duration(seconds: 10));
    await _pumpChallengeTransition(tester);
    expect(prompt.stopCalls, 1);
    expect(media.recordingStarts, 0);
    expect(
      find.text('Chưa phát được câu hỏi. Bạn bấm nghe lại nhé.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Android timeout cannot become success when stop completes speech',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _usePhoneSurface(tester);
      final media = _FakeLessonMediaService();
      final prompt = _StopCompletesPromptVoiceService();
      await tester.pumpWidget(
        _subject(startAge: 7, mediaService: media, voicePromptService: prompt),
      );
      await _pumpChallengeTransition(tester);
      await tester.pump(const Duration(seconds: 10));
      await _pumpChallengeTransition(tester);
      expect(prompt.stopCalls, 1);
      expect(media.recordingStarts, 0);
      expect(
        find.text('Chưa phát được câu hỏi. Bạn bấm nghe lại nhé.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'auto-stops, waits for a correct score, then opens challenge two',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _FakeLessonMediaService();
      final evaluator = _ControlledAttemptEvaluator();
      await tester.pumpWidget(
        _subject(
          startAge: 7,
          mediaService: mediaService,
          attemptEvaluator: evaluator,
          challenges: const <ListeningChallengeContent>[
            ListeningChallengeContent(
              id: 'challenge-1',
              format: 'VI_TO_EN',
              prompt: 'Where is the library?',
              choices: <String>['Go straight.', 'It is five dollars.'],
              correctAnswer: 'Go straight.',
              correctVietnamese: 'Đi thẳng.',
              targetId: 'target-1',
            ),
            ListeningChallengeContent(
              id: 'challenge-2',
              format: 'VI_TO_EN',
              prompt: 'How are you?',
              choices: <String>['I am fine.', 'I am eight.'],
              correctAnswer: 'I am fine.',
              correctVietnamese: 'Con khỏe.',
              targetId: 'target-2',
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(mediaService.recordingStarts, 1);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      expect(mediaService.recordingStops, 1);
      expect(evaluator.evaluationCalls, 1);
      expect(find.text('Câu 1/2'), findsOneWidget);
      expect(mediaService.recordingStarts, 1);

      evaluator.complete(LessonAttemptOutcome.good);
      await _pumpChallengeTransition(tester);

      expect(find.text('Câu 2/2'), findsOneWidget);
      expect(mediaService.recordingStarts, 2);
      expect(find.text('Dừng và chấm'), findsOneWidget);
    },
  );

  testWidgets('moves on after two retries instead of recording forever', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _FakeLessonMediaService();
    final evaluator = _QueuedAttemptEvaluator(<LessonAttemptOutcome>[
      LessonAttemptOutcome.retry,
      LessonAttemptOutcome.retry,
    ]);
    final voicePrompt = _RecordingVoicePromptService();
    final earnedStars = <String>[];
    final needsPractice = <String>[];
    await tester.pumpWidget(
      _subject(
        startAge: 7,
        mediaService: mediaService,
        attemptEvaluator: evaluator,
        voicePromptService: voicePrompt,
        onStarEarned: (starId, _, _) async => earnedStars.add(starId),
        onNeedsPractice: (targetId, _, _) async => needsPractice.add(targetId),
        challenges: const <ListeningChallengeContent>[
          ListeningChallengeContent(
            id: 'challenge-1',
            format: 'VI_TO_EN',
            prompt: 'Where is the library?',
            choices: <String>['Go straight.', 'It is five dollars.'],
            correctAnswer: 'Go straight.',
            correctVietnamese: 'Đi thẳng.',
            targetId: 'target-1',
          ),
          ListeningChallengeContent(
            id: 'challenge-2',
            format: 'VI_TO_EN',
            prompt: 'How are you?',
            choices: <String>['I am fine.', 'I am eight.'],
            correctAnswer: 'I am fine.',
            correctVietnamese: 'Con khỏe.',
            targetId: 'target-2',
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump();
    expect(find.text('Câu 1/2'), findsOneWidget);
    expect(mediaService.recordingStarts, 2);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump();
    expect(find.text('Câu 2/2'), findsOneWidget);
    expect(evaluator.evaluationCalls, 2);
    expect(mediaService.recordingStarts, 3);
    expect(earnedStars, isEmpty);
    expect(needsPractice, <String>['challenge:1']);
    expect(
      voicePrompt.spoken,
      containsAllInOrder(<String>[
        'vi-VN|Bạn thử lại nhé.',
        'vi-VN|Where is the library?',
        'vi-VN|Bạn trả lời nhé',
        'vi-VN|Chưa đúng. Mình nghe câu đúng nhé.',
        'en-US|Go straight.',
      ]),
    );
    expect(
      voicePrompt.spoken.where((text) => text == 'en-US|Go straight.'),
      hasLength(1),
    );
    expect(mediaService.completedPlaybackUris, hasLength(2));
    expect(
      mediaService.completedPlaybackGains,
      everyElement(lessonRecordingPlaybackGainDb),
    );
  });

  testWidgets('pauses directly after the second unusable response', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _FakeLessonMediaService();
    final evaluator = _QueuedAttemptEvaluator(<LessonAttemptOutcome>[
      LessonAttemptOutcome.noResponse,
      LessonAttemptOutcome.unclear,
    ]);
    await tester.pumpWidget(
      _subject(
        startAge: 7,
        mediaService: mediaService,
        attemptEvaluator: evaluator,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.pump(const Duration(seconds: 6));
    await _pumpChallengeTransition(tester);
    expect(mediaService.recordingStarts, 2);
    expect(
      find.byKey(const Key('challenge-resume-after-no-response')),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 6));
    await _pumpChallengeTransition(tester);
    expect(mediaService.recordingStarts, 2);
    expect(
      find.byKey(const Key('challenge-resume-after-no-response')),
      findsOneWidget,
    );
  });

  testWidgets(
    'second answer correct gets correct feedback without HOMI sample',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _FakeLessonMediaService();
      final evaluator = _QueuedAttemptEvaluator(<LessonAttemptOutcome>[
        LessonAttemptOutcome.retry,
        LessonAttemptOutcome.good,
      ]);
      final voicePrompt = _RecordingVoicePromptService();
      await tester.pumpWidget(
        _subject(
          startAge: 7,
          mediaService: mediaService,
          attemptEvaluator: evaluator,
          voicePromptService: voicePrompt,
          challenges: const <ListeningChallengeContent>[
            ListeningChallengeContent(
              id: 'challenge-1',
              format: 'VI_TO_EN',
              prompt: 'Where is the library?',
              choices: <String>['Go straight.', 'It is five dollars.'],
              correctAnswer: 'Go straight.',
              correctVietnamese: 'Đi thẳng.',
              targetId: 'target-1',
            ),
            ListeningChallengeContent(
              id: 'challenge-2',
              format: 'VI_TO_EN',
              prompt: 'How are you?',
              choices: <String>['I am fine.', 'I am eight.'],
              correctAnswer: 'I am fine.',
              correctVietnamese: 'Con khỏe.',
              targetId: 'target-2',
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.pump(const Duration(seconds: 6));
      await _pumpChallengeTransition(tester);
      expect(mediaService.recordingStarts, 2);

      await tester.pump(const Duration(seconds: 6));
      await _pumpChallengeTransition(tester);

      expect(find.text('Câu 2/2'), findsOneWidget);
      expect(voicePrompt.spoken, contains('vi-VN|Đúng rồi!'));
      expect(voicePrompt.spoken, isNot(contains('vi-VN|HOMI nói mẫu nhé.')));
      expect(evaluator.evaluationCalls, 2);
      expect(mediaService.completedPlaybackUris, hasLength(2));
    },
  );

  testWidgets('iOS scores a challenge on device without calling the backend', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _usePhoneSurface(tester);
    final mediaService = _FakeLessonMediaService();
    final speechInput = _FakeLessonEnglishSpeechInput('Go straight.');
    final backendEvaluator = _FailIfCalledAttemptEvaluator();
    await tester.pumpWidget(
      _subject(
        startAge: 7,
        mediaService: mediaService,
        iosSpeechInput: speechInput,
        attemptEvaluator: backendEvaluator,
        challenges: const <ListeningChallengeContent>[
          ListeningChallengeContent(
            id: 'challenge-1',
            format: 'VI_TO_EN',
            prompt: 'Where is the library?',
            choices: <String>['Go straight.', 'It is five dollars.'],
            correctAnswer: 'Go straight.',
            correctVietnamese: 'Đi thẳng.',
            targetId: 'target-1',
          ),
          ListeningChallengeContent(
            id: 'challenge-2',
            format: 'VI_TO_EN',
            prompt: 'How are you?',
            choices: <String>['I am fine.', 'I am eight.'],
            correctAnswer: 'I am fine.',
            correctVietnamese: 'Con khỏe.',
            targetId: 'target-2',
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(speechInput.startCalls, 1);
    expect(mediaService.recordingStarts, 0);
    expect(mediaService.nativeCaptureHandoffs, 1);

    await tester.pump(const Duration(seconds: 6));
    await _pumpChallengeTransition(tester);

    expect(speechInput.stopCalls, 1);
    expect(backendEvaluator.evaluationCalls, 0);
    expect(find.text('Câu 2/2'), findsOneWidget);
    expect(speechInput.startCalls, 2);
    expect(find.text('Dừng và chấm'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'iOS recognition failure retains its local WAV without backend scoring',
    (tester) async {
      await _usePhoneSurface(tester);
      final media = _FakeLessonMediaService()
        ..finalizedRecordingPath = '/recordings/answer-normalized.m4a';
      final speech = _RecordingFailureIosInput();
      final backend = _FailIfCalledAttemptEvaluator();
      addTearDown(speech.dispose);
      await tester.pumpWidget(
        _subject(
          startAge: 7,
          mediaService: media,
          iosSpeechInput: speech,
          attemptEvaluator: backend,
        ),
      );
      await _pumpChallengeTransition(tester);
      await tester.tap(find.byKey(const Key('lesson-challenge-record-button')));
      await _pumpChallengeTransition(tester);
      expect(speech.takeRecordingCalls, 1);
      expect(media.completedPlaybackUris, <Uri>[
        Uri.file('/recordings/answer-normalized.m4a'),
      ]);
      expect(media.finalizedRecordingPaths, <String>['/recordings/answer.wav']);
      expect(media.recordingStarts, 0);
      expect(backend.evaluationCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iOS normalization failure falls back to the valid challenge WAV',
    (tester) async {
      await _usePhoneSurface(tester);
      final media = _FakeLessonMediaService()
        ..finalizationError = StateError('normalizer unavailable');
      final speech = _RecordingFailureIosInput();
      addTearDown(speech.dispose);
      await tester.pumpWidget(
        _subject(
          startAge: 7,
          mediaService: media,
          iosSpeechInput: speech,
          attemptEvaluator: _FailIfCalledAttemptEvaluator(),
        ),
      );
      await _pumpChallengeTransition(tester);
      await tester.tap(find.byKey(const Key('lesson-challenge-record-button')));
      await _pumpChallengeTransition(tester);

      expect(media.completedPlaybackUris, <Uri>[
        Uri.file('/recordings/answer.wav'),
      ]);
      expect(media.finalizedRecordingPaths, <String>['/recordings/answer.wav']);
      expect(media.externalRegistrationCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iOS MAIN cancels a pending native start without cancelling a later turn',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _usePhoneSurface(tester);
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final startGate = Completer<void>();
      final speechInput = _FakeLessonEnglishSpeechInput(
        'Go straight.',
        startGate: startGate,
      );
      final media = _FakeLessonMediaService();
      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: _subject(
            startAge: 7,
            mediaService: media,
            iosSpeechInput: speechInput,
            attemptEvaluator: _FailIfCalledAttemptEvaluator(),
          ),
        ),
      );
      await _pumpChallengeTransition(tester);
      expect(speechInput.startCalls, 1);
      await registry.pauseForMainAssistant();
      expect(speechInput.cancelCalls, 1);
      startGate.complete();
      await _pumpChallengeTransition(tester);
      expect(speechInput.cancelCalls, 1);
      expect(media.recordingStarts, 0);
      expect(media.nativeCaptureHandoffs, 0);
      expect(find.text('Dừng và chấm'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'iOS native start failure does not upload audio through a hidden fallback',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _usePhoneSurface(tester);
      final media = _FakeLessonMediaService();
      final backend = _FailIfCalledAttemptEvaluator();
      final speechInput = _FakeLessonEnglishSpeechInput(
        '',
        startError: const StreamingSpeechInputException(
          'Bộ nhận diện trên iPhone chưa sẵn sàng.',
          code: 'ON_DEVICE_SPEECH_UNAVAILABLE',
        ),
      );
      await tester.pumpWidget(
        _subject(
          startAge: 7,
          mediaService: media,
          iosSpeechInput: speechInput,
          attemptEvaluator: backend,
        ),
      );
      await _pumpChallengeTransition(tester);
      expect(media.recordingStarts, 0);
      expect(backend.evaluationCalls, 0);
      expect(speechInput.cancelCalls, 1);
      expect(find.textContaining('iPhone chưa sẵn sàng'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'iOS challenge surfaces Speech permission denial without backend fallback',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _usePhoneSurface(tester);
      final mediaService = _FakeLessonMediaService();
      final speechInput = _FakeLessonEnglishSpeechInput(
        '',
        startError: const StreamingSpeechInputException(
          'Hãy bật Nhận dạng giọng nói cho HOMI trong Cài đặt.',
          code: 'SPEECH_PERMISSION_DENIED',
        ),
      );
      final backendEvaluator = _FailIfCalledAttemptEvaluator();

      await tester.pumpWidget(
        _subject(
          startAge: 7,
          mediaService: mediaService,
          iosSpeechInput: speechInput,
          attemptEvaluator: backendEvaluator,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(speechInput.startCalls, 1);
      expect(mediaService.recordingStarts, 0);
      expect(backendEvaluator.evaluationCalls, 0);
      expect(find.textContaining('Nhận dạng giọng nói'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

Widget _subject({
  required int startAge,
  ListeningLessonContent? lesson,
  _FakeLessonMediaService? mediaService,
  List<ListeningChallengeContent>? challenges,
  VoicePromptService? voicePromptService,
  LessonAttemptEvaluator? attemptEvaluator,
  LessonEnglishSpeechInput? iosSpeechInput,
  Future<void> Function(String, String, String)? onStarEarned,
  Future<void> Function(String, String, String)? onNeedsPractice,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: LessonChallengeScreen(
      language: DisplayLanguage.vietnamese,
      startAge: startAge,
      lesson: lesson ?? _lesson(),
      challenges:
          challenges ??
          const <ListeningChallengeContent>[
            ListeningChallengeContent(
              id: 'challenge-1',
              format: 'VI_TO_EN',
              prompt: 'Where is the library?',
              choices: <String>['Go straight.', 'It is five dollars.'],
              correctAnswer: 'Go straight.',
              correctVietnamese: 'Đi thẳng.',
              targetId: 'target-1',
            ),
          ],
      mediaService: mediaService ?? _FakeLessonMediaService(),
      attemptEvaluator: attemptEvaluator ?? const _AlwaysGoodAttemptEvaluator(),
      voicePromptService: voicePromptService ?? const _FakeVoicePromptService(),
      iosSpeechInput: iosSpeechInput,
      onStarEarned: onStarEarned,
      onNeedsPractice: onNeedsPractice,
    ),
  );
}

ListeningLessonContent _lesson() {
  return const ListeningLessonContent(
    id: 'challenge-test-lesson',
    number: 1,
    titleVi: 'Bài kiểm tra',
    titleEn: 'Challenge test',
    intro: '',
    outro: '',
    estimatedMinutes: 1,
    sentences: <ListeningSentenceContent>[],
    rolePlay: ListeningRolePlayContent(
      scenarioVi: 'Trong lớp học',
      openingHint: 'Can I...',
      turns: <ListeningRolePlayTurn>[
        ListeningRolePlayTurn(
          speaker: ListeningRolePlaySpeaker.child,
          english: 'Can I come in?',
          vietnamese: 'Con vào được không?',
        ),
      ],
    ),
  );
}

class _FakeLessonMediaService extends LessonMediaService {
  @override
  Future<String> recordingPath({
    required String lessonId,
    required int sentenceNumber,
    String? extension,
  }) async => '/recordings/answer.${extension ?? 'm4a'}';

  int recordingStarts = 0;
  int recordingStops = 0;
  int selectedOutputPreparations = 0;
  int nativeCaptureHandoffs = 0;
  String? finalizedRecordingPath;
  Object? finalizationError;
  int externalRegistrationCalls = 0;
  final List<String> finalizedRecordingPaths = <String>[];
  final List<Uri> completedPlaybackUris = <Uri>[];
  final List<double> completedPlaybackGains = <double>[];

  @override
  Future<LessonRecording> finalizeExternalRecording({
    required LessonRecording recording,
  }) async {
    finalizedRecordingPaths.add(recording.filePath);
    final error = finalizationError;
    if (error != null) throw error;
    return LessonRecording(
      filePath: finalizedRecordingPath ?? recording.filePath,
      duration: recording.duration,
    );
  }

  @override
  Future<LessonRecording> registerExternalRecording({
    required LessonRecording recording,
    required String lessonId,
    required String lessonTitle,
    required String sentenceId,
    required int sentenceNumber,
    required String english,
    required String vietnamese,
  }) async {
    externalRegistrationCalls += 1;
    return recording;
  }

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = 8.0,
    bool fixedPlaybackGain = false,
  }) async {
    completedPlaybackUris.add(uri);
    completedPlaybackGains.add(playbackGainDb);
  }

  @override
  Future<void> prepareSelectedLessonOutput() async {
    selectedOutputPreparations += 1;
  }

  @override
  void handoffSelectedLessonOutputToNativeCapture() {
    nativeCaptureHandoffs += 1;
  }

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
    recordingStarts += 1;
  }

  @override
  Future<LessonRecording> stopRecording() async {
    recordingStops += 1;
    return const LessonRecording(
      filePath: 'test-recording.m4a',
      duration: Duration(seconds: 1),
    );
  }
}

class _AlwaysGoodAttemptEvaluator implements LessonAttemptEvaluator {
  const _AlwaysGoodAttemptEvaluator();

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
  }) async => LessonAttemptOutcome.good;
}

class _ControlledAttemptEvaluator implements LessonAttemptEvaluator {
  final Completer<LessonAttemptOutcome> _completion =
      Completer<LessonAttemptOutcome>();
  int evaluationCalls = 0;

  void complete(LessonAttemptOutcome outcome) => _completion.complete(outcome);

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
  }) {
    evaluationCalls += 1;
    return _completion.future;
  }
}

class _QueuedAttemptEvaluator implements LessonAttemptEvaluator {
  _QueuedAttemptEvaluator(this.outcomes);

  final List<LessonAttemptOutcome> outcomes;
  int evaluationCalls = 0;

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
    final outcome = outcomes[evaluationCalls];
    evaluationCalls += 1;
    return outcome;
  }
}

class _FailIfCalledAttemptEvaluator implements LessonAttemptEvaluator {
  int evaluationCalls = 0;

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
    evaluationCalls += 1;
    throw StateError('Backend must not be called for iOS on-device scoring.');
  }
}

class _RecordingFailureIosInput extends IOSStreamingSpeechInput {
  _RecordingFailureIosInput()
    : super(eventStream: const Stream<dynamic>.empty());

  int takeRecordingCalls = 0;

  @override
  Future<void> startLessonEnglishRecognitionWithRecording(String path) async {}

  @override
  Future<StreamingSpeechCapture> stop() async {
    throw const StreamingSpeechInputException(
      'Chưa nghe rõ.',
      code: 'SF_SPEECH_RECOGNIZER_FAILED',
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  AudioCapture? takeLessonRecordingAudioCapture() {
    takeRecordingCalls++;
    return const AudioCapture(
      filePath: '/recordings/answer.wav',
      mimeType: 'audio/wav',
      duration: Duration(seconds: 1),
      inputLabel: 'Apple Speech',
      isBluetoothInput: false,
      initialNoiseRms: null,
    );
  }
}

class _FakeLessonEnglishSpeechInput implements LessonEnglishSpeechInput {
  _FakeLessonEnglishSpeechInput(
    this.transcript, {
    this.startError,
    this.startGate,
  });

  final String transcript;
  final Object? startError;
  final Completer<void>? startGate;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> startLessonEnglishRecognition() async {
    startCalls += 1;
    final error = startError;
    if (error != null) throw error;
    await startGate?.future;
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    stopCalls += 1;
    return StreamingSpeechCapture(
      sourceText: transcript,
      duration: const Duration(seconds: 1),
      inputLabel: 'H20 Apple Speech',
      confidence: 1,
      firstResultMs: 120,
      finalAfterStopMs: 80,
      alternatives: const <String>[],
    );
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }
}

class _FakeVoicePromptService implements VoicePromptService {
  const _FakeVoicePromptService();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> stop() async {}
}

class _RecordingVoicePromptService implements VoicePromptService {
  final List<String> spoken = <String>[];

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spoken.add('$locale|$text');
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);

  @override
  Future<void> stop() async {}
}

class _KeyedChallengeVoicePromptService extends _RecordingVoicePromptService
    implements
        KeyedVoicePromptService,
        KeyedSelectedMediaOutputVoicePromptService,
        KeyedAuthoredPromptBudgetProvider {
  _KeyedChallengeVoicePromptService({this.gateQuestion = false});

  final bool gateQuestion;
  final questionGate = Completer<void>();
  final List<String> audioKeys = <String>[];
  final List<String> budgetKeys = <String>[];

  @override
  Future<Duration?> authoredPromptBudgetForKey(
    String audioKey, {
    required String text,
    String locale = 'vi-VN',
  }) async {
    budgetKeys.add(audioKey);
    return const Duration(seconds: 25);
  }

  @override
  Future<void> speakAndWaitWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  }) async {
    audioKeys.add(audioKey);
    if (gateQuestion && audioKey.endsWith('.prompt.vi')) {
      await questionGate.future;
    }
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutputWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  }) => speakAndWaitWithAudioKey(audioKey, text, locale: locale);
}

class _FailingVoicePromptService extends _RecordingVoicePromptService {
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    throw StateError('H20 route unavailable');
  }
}

class _GatedChallengeCuePrompt extends _RecordingVoicePromptService
    implements SpeechReadyCuePlayer {
  final cue = Completer<void>();
  bool cueStarted = false;
  @override
  Future<void> playSpeechReadyCue() async {
    cueStarted = true;
    await cue.future;
  }
}

class _FailingRetryQuestionPrompt extends _RecordingVoicePromptService {
  int questionCalls = 0;
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    if (text == 'Where is the library?' && ++questionCalls == 2) {
      throw StateError('Question playback unavailable');
    }
    await super.speakAndWait(text, locale: locale);
  }
}

class _GatedChallengeFeedbackPrompt extends _RecordingVoicePromptService {
  final feedback = Completer<void>();
  bool feedbackStarted = false;
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    await super.speakAndWait(text, locale: locale);
    if (text == 'Đúng rồi!') {
      feedbackStarted = true;
      await feedback.future;
    }
  }
}

class _LongAuthoredChallengePrompt extends _RecordingVoicePromptService
    implements AuthoredPromptBudgetProvider {
  final completion = Completer<void>();
  int calls = 0;
  int stopCalls = 0;

  @override
  Future<Duration?> authoredPromptBudget(
    String text, {
    String locale = 'vi-VN',
  }) async => const Duration(seconds: 25);

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    calls++;
    if (calls == 1) await completion.future;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

class _MissingSecondFinishVoicePromptService implements VoicePromptService {
  int speakCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) {
    speakCalls += 1;
    if (speakCalls == 1) {
      return Future<void>.value();
    }
    return Completer<void>().future;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}

class _MissingFirstFinishVoicePromptService implements VoicePromptService {
  int stopCalls = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      Completer<void>().future;

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}

class _StopCompletesPromptVoiceService
    extends _MissingSecondFinishVoicePromptService {
  final completion = Completer<void>();
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    speakCalls += 1;
    if (speakCalls > 1) await completion.future;
  }

  @override
  Future<void> stop() async {
    await super.stop();
    if (!completion.isCompleted) completion.complete();
  }
}

/// Flushes a prompt/scoring handoff without advancing the six-second answer
/// timer for the newly opened microphone turn.
Future<void> _pumpChallengeTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
