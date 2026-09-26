import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/homi_ui.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/audio/audio_gain.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../l10n/display_language.dart';
import '../../voice_navigation/domain/main_assistant_audio_keys.dart';
import '../../voice_navigation/domain/master_navigation_contract.dart';
import '../application/lesson_attempt_evaluator.dart';
import '../application/lesson_media_service.dart';
import '../application/lesson_recording_endpoint_detector.dart';
import '../domain/lesson_guide_flow.dart';
import '../domain/listening_audio_keys.dart';
import '../domain/listening_content.dart';

/// Runs the single authored Challenge selected for the current Core.
///
/// Legacy role-play data remains readable during migration but is deliberately
/// ignored by this runtime. The microphone is the answer control: a child must
/// say the English answer rather than selecting A/B.
class LessonChallengeScreen extends StatefulWidget {
  const LessonChallengeScreen({
    required this.language,
    required this.startAge,
    required this.lesson,
    required this.challenges,
    required this.mediaService,
    this.attemptEvaluator,
    this.voicePromptService,
    this.iosSpeechInput,
    this.onStarEarned,
    this.onStarEarnedWithResult,
    this.onStarEarnedWithAudioResult,
    this.onNeedsPractice,
    this.onChallengeResolved,
    super.key,
  });

  final DisplayLanguage language;
  final int startAge;
  final ListeningLessonContent lesson;
  final List<ListeningChallengeContent> challenges;
  final LessonMediaService mediaService;
  final LessonAttemptEvaluator? attemptEvaluator;
  final VoicePromptService? voicePromptService;
  final LessonEnglishSpeechInput? iosSpeechInput;
  final Future<void> Function(
    String targetId,
    String english,
    String vietnamese,
  )?
  onStarEarned;
  final Future<bool> Function(String starId, String english, String vietnamese)?
  onStarEarnedWithResult;
  final Future<bool> Function(
    String starId,
    String english,
    String vietnamese,
    String? correctAudioPath,
  )?
  onStarEarnedWithAudioResult;
  final Future<void> Function(
    String targetId,
    String english,
    String vietnamese,
  )?
  onNeedsPractice;
  final Future<void> Function(
    ListeningChallengeContent challenge,
    bool correct,
  )?
  onChallengeResolved;

  @override
  State<LessonChallengeScreen> createState() => _LessonChallengeScreenState();
}

class _LessonChallengeScreenState extends State<LessonChallengeScreen>
    implements ActiveLearningModuleController, ActiveLearningVoiceContext {
  @override
  ActiveLearningVoiceNode get mainVoiceNode =>
      ActiveLearningVoiceNode.challenge;

  @override
  String get mainVoicePrompt => MasterNavigationContract.challengeControlPrompt;
  static const Duration _promptCompletionTimeout = Duration(seconds: 10);

  late final LessonAttemptEvaluator _attemptEvaluator;
  late final bool _ownsAttemptEvaluator;

  VoicePromptService? _voicePromptService;
  bool _ownsVoicePromptService = false;
  int _challengeIndex = 0;
  int _attemptNumber = 0;
  bool _playingPrompt = false;
  bool _recording = false;
  bool _recordingStartPending = false;
  bool _recordingUsesIosSpeech = false;
  bool _busy = false;
  String? _message;
  int _request = 0;
  int _mainPauseGeneration = 0;
  final LessonRecordingEndpointDetector _recordingEndpointDetector =
      LessonRecordingEndpointDetector();
  Timer? _promptCompletionTimer;
  Completer<void>? _promptCompletionWaiter;
  bool _pausedForMainAssistant = false;
  bool _pausedAfterNoResponse = false;
  int _invalidResponseCount = 0;
  String? _activeAttemptAudioPath;
  StreamSubscription<LessonMediaException>? _recordingErrorSubscription;
  ActiveLearningModuleRegistry? _activeModuleRegistry;
  Object? _activeModuleRegistration;

  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.listeningLesson;

  @override
  bool get isPausedForMain => _pausedForMainAssistant;

  ListeningChallengeContent get _challenge =>
      widget.challenges[_challengeIndex];

  bool get _usesIosOnDeviceRecognition =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      widget.iosSpeechInput != null;

  VoicePromptService get _prompt {
    final current = _voicePromptService;
    if (current != null) return current;
    _ownsVoicePromptService = true;
    return _voicePromptService = createVoicePromptService(
      owner: AudioTurnOwner.listeningLesson,
    );
  }

  @override
  void initState() {
    super.initState();
    _ownsAttemptEvaluator = widget.attemptEvaluator == null;
    _attemptEvaluator =
        widget.attemptEvaluator ?? createDefaultLessonAttemptEvaluator();
    _voicePromptService = widget.voicePromptService;
    _recordingErrorSubscription = widget.mediaService.recordingErrors.listen(
      _handleRecordingInterrupted,
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_playCurrentPrompt()),
    );
  }

  void _handleRecordingInterrupted(LessonMediaException error) {
    if (!mounted ||
        _pausedForMainAssistant ||
        (!_recording && !_recordingStartPending)) {
      return;
    }
    // LessonMediaService has already closed the failed native capture. Make
    // the pending async start stale too, otherwise its late completion could
    // put the Challenge UI back into a recording state with no microphone.
    _request += 1;
    _recordingEndpointDetector.cancel();
    setState(() {
      _recording = false;
      _recordingStartPending = false;
      _recordingUsesIosSpeech = false;
      _busy = false;
      _activeAttemptAudioPath = null;
      _message = _friendlyError(error);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = ActiveLearningModuleScope.maybeOf(context);
    if (identical(registry, _activeModuleRegistry)) return;
    final oldRegistration = _activeModuleRegistration;
    if (oldRegistration != null) {
      _activeModuleRegistry?.unregister(oldRegistration);
    }
    _activeModuleRegistry = registry;
    _activeModuleRegistration = registry?.register(this);
  }

  @override
  void dispose() {
    final wasPlayingPrompt = _playingPrompt;
    final wasRecording =
        _recording || _recordingStartPending || _recordingUsesIosSpeech;
    final registration = _activeModuleRegistration;
    if (registration != null) {
      _activeModuleRegistry?.unregister(registration);
    }
    _request += 1;
    _mainPauseGeneration += 1;
    unawaited(_recordingErrorSubscription?.cancel());
    _recordingEndpointDetector.cancel();
    _promptCompletionTimer?.cancel();
    _promptCompletionTimer = null;
    final promptWaiter = _promptCompletionWaiter;
    _promptCompletionWaiter = null;
    if (promptWaiter != null && !promptWaiter.isCompleted) {
      promptWaiter.complete();
    }
    // The parent lesson reuses these services immediately after a successful
    // Challenge pop to announce the completion choice and open its mic. Do not
    // let this disposed route stop that new turn; only tear down work that was
    // actually active on this route.
    if (wasPlayingPrompt) {
      unawaited(widget.mediaService.stopPlayback());
    }
    if (wasRecording) {
      if (_recordingUsesIosSpeech && widget.iosSpeechInput != null) {
        unawaited(widget.iosSpeechInput!.cancel());
      } else {
        unawaited(widget.mediaService.cancelRecording());
      }
    }
    final prompt = _voicePromptService;
    if (prompt != null) {
      if (_ownsVoicePromptService) {
        unawaited(prompt.dispose());
      } else if (wasPlayingPrompt) {
        unawaited(prompt.stop());
      }
    }
    if (_ownsAttemptEvaluator &&
        _attemptEvaluator is DisposableLessonAttemptEvaluator) {
      (_attemptEvaluator as DisposableLessonAttemptEvaluator).dispose();
    }
    super.dispose();
  }

  @override
  Future<void> pauseForMainAssistant() async {
    _pausedForMainAssistant = true;
    _request += 1;
    _mainPauseGeneration += 1;
    _recordingEndpointDetector.cancel();
    _promptCompletionTimer?.cancel();
    _promptCompletionTimer = null;
    final waiter = _promptCompletionWaiter;
    _promptCompletionWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    final wasRecording = _recording || _recordingStartPending;
    final usedIosSpeech = _recordingUsesIosSpeech;
    if (mounted) {
      setState(() {
        _playingPrompt = false;
        _recording = false;
        _recordingStartPending = false;
        _recordingUsesIosSpeech = false;
        _busy = false;
        _message = 'Phần thử thách đang tạm dừng.';
      });
    }
    await Future.wait<void>(<Future<void>>[
      widget.mediaService.stopPlayback().catchError((Object _) {}),
      if (_voicePromptService != null)
        _voicePromptService!.stop().catchError((Object _) {}),
      if (wasRecording && usedIosSpeech && widget.iosSpeechInput != null)
        widget.iosSpeechInput!.cancel().catchError((Object _) {})
      else if (wasRecording)
        widget.mediaService.cancelRecording().catchError((Object _) {}),
    ]);
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    if (!mounted) return const ActiveLearningCommandResult.unavailable();
    switch (command) {
      case ActiveLearningCommand.resume:
        _pausedForMainAssistant = false;
        if (_pausedAfterNoResponse) {
          unawaited(_resumeAfterNoResponse());
          return const ActiveLearningCommandResult.handled();
        }
        unawaited(_playCurrentPrompt(announceResume: true));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.replayCurrent:
        _pausedForMainAssistant = false;
        unawaited(_replayCurrent());
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.stop:
        await pauseForMainAssistant();
        return const ActiveLearningCommandResult.handled(
          spokenReply: 'Đã dừng phần thử thách.',
        );
      case ActiveLearningCommand.exitToHome:
        await pauseForMainAssistant();
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.nextItem:
      case ActiveLearningCommand.previousItem:
      case ActiveLearningCommand.nextLesson:
      case ActiveLearningCommand.previousLesson:
      case ActiveLearningCommand.restart:
      case ActiveLearningCommand.vocabularyParentAdded:
      case ActiveLearningCommand.vocabularyPracticeAgain:
      case ActiveLearningCommand.vocabularyStars:
      case ActiveLearningCommand.vocabularyLatest:
      case ActiveLearningCommand.vocabularyAll:
        return const ActiveLearningCommandResult.unavailable(
          spokenReply:
              'Các nút câu trước, câu sau và nghe lại chỉ dùng trong phần luyện câu.',
        );
    }
  }

  Future<bool> _playCurrentPrompt({
    bool allowBusy = false,
    bool openMicrophone = true,
    bool announceResume = false,
  }) async {
    if (_pausedForMainAssistant ||
        !mounted ||
        _recording ||
        (_busy && !allowBusy)) {
      return false;
    }
    final request = ++_request;
    setState(() {
      _playingPrompt = true;
      _message = null;
    });
    try {
      // Own the selected H20 route before TTS starts and keep it through the
      // transition to recording. On iOS, allowing the prompt lease to be the
      // only owner makes AVAudioSession deactivate at didFinish, so the
      // automatic microphone opening can be lost during route renegotiation.
      await _prepareSelectedLessonOutputWithRetry(request);
      if (!mounted || request != _request) return false;
      if (announceResume) {
        await _speakPromptAndWait(
          'Mình tiếp tục câu thử thách nhé.',
          audioKey: ListeningAudioKeys.challengeResume,
        );
        if (!mounted || request != _request) return false;
      }
      await _speakPromptAndWait(
        _challenge.prompt,
        audioKey: ListeningAudioKeys.challengePrompt(_challenge.id),
      );
      if (!mounted || request != _request) return false;
      await _speakPromptAndWait(
        'Bạn trả lời nhé',
        audioKey: ListeningAudioKeys.challengeAnswerHandoff,
        // The authored question above has already completed. On iOS a small
        // number of AVSpeechSynthesizer turns play this short hand-off cue but
        // omit didFinish; that must not strand an otherwise audible question.
        allowIosCompletionCallbackTimeout: true,
      );
    } catch (error) {
      if (mounted && request == _request) {
        setState(
          () => _message = 'Chưa phát được câu hỏi. Bạn bấm nghe lại nhé.',
        );
      }
      // A failed H20/TTS turn must not jump straight into capture.
      return false;
    } finally {
      if (mounted && request == _request) {
        setState(() => _playingPrompt = false);
      }
    }
    if (_pausedForMainAssistant ||
        !mounted ||
        request != _request ||
        _recording ||
        (_busy && !allowBusy)) {
      return false;
    }
    if (openMicrophone) await _startRecording();
    return true;
  }

  Future<void> _prepareSelectedLessonOutputWithRetry(int request) async {
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
    } catch (_) {
      if (!mounted || _pausedForMainAssistant || request != _request) rethrow;
      // BLE/HFP can report the new route a fraction after the screen opens.
      // One short retry covers that transition without replaying the question
      // or silently falling back to the phone speaker/microphone.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || _pausedForMainAssistant || request != _request) rethrow;
      await widget.mediaService.prepareSelectedLessonOutput();
    }
  }

  Future<void> _replayCurrent() async {
    if (_recording) {
      _recordingEndpointDetector.cancel();
      if (_recordingUsesIosSpeech && widget.iosSpeechInput != null) {
        await widget.iosSpeechInput!.cancel().catchError((Object _) {});
      } else {
        await widget.mediaService.cancelRecording().catchError((Object _) {});
      }
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordingUsesIosSpeech = false;
      });
    }
    await _playCurrentPrompt();
  }

  Future<void> _speakPromptAndWait(
    String text, {
    String locale = 'vi-VN',
    String? audioKey,
    bool allowIosCompletionCallbackTimeout = false,
  }) async {
    final request = _request;
    final prompt = _prompt;
    final budget =
        audioKey != null && prompt is KeyedAuthoredPromptBudgetProvider
        ? await (prompt as KeyedAuthoredPromptBudgetProvider)
              .authoredPromptBudgetForKey(audioKey, text: text, locale: locale)
              .timeout(const Duration(milliseconds: 700), onTimeout: () => null)
        : prompt is AuthoredPromptBudgetProvider
        ? await (prompt as AuthoredPromptBudgetProvider)
              .authoredPromptBudget(text, locale: locale)
              .timeout(const Duration(milliseconds: 700), onTimeout: () => null)
        : null;
    if (!mounted || _pausedForMainAssistant || request != _request) return;
    _promptCompletionTimer?.cancel();
    final previousWaiter = _promptCompletionWaiter;
    if (previousWaiter != null && !previousWaiter.isCompleted) {
      previousWaiter.complete();
    }

    final waiter = Completer<void>();
    var timedOut = false;
    _promptCompletionWaiter = waiter;
    unawaited(() async {
      try {
        final voicePrompt = _prompt;
        if (audioKey != null &&
            voicePrompt is KeyedSelectedMediaOutputVoicePromptService) {
          await (voicePrompt as KeyedSelectedMediaOutputVoicePromptService)
              .speakAndWaitOnSelectedMediaOutputWithAudioKey(
                audioKey,
                text,
                locale: locale,
              );
        } else if (audioKey != null && voicePrompt is KeyedVoicePromptService) {
          await (voicePrompt as KeyedVoicePromptService)
              .speakAndWaitWithAudioKey(audioKey, text, locale: locale);
        } else if (voicePrompt is SelectedMediaOutputVoicePromptService) {
          await (voicePrompt as SelectedMediaOutputVoicePromptService)
              .speakAndWaitOnSelectedMediaOutput(text, locale: locale);
        } else {
          await voicePrompt.speakAndWait(text, locale: locale);
        }
        if (!timedOut && !waiter.isCompleted) waiter.complete();
      } catch (error, stackTrace) {
        if (!timedOut && !waiter.isCompleted) {
          waiter.completeError(error, stackTrace);
        }
      }
    }());
    _promptCompletionTimer = Timer(budget ?? _promptCompletionTimeout, () {
      unawaited(() async {
        if (!mounted ||
            _pausedForMainAssistant ||
            request != _request ||
            !identical(_promptCompletionWaiter, waiter)) {
          return;
        }
        // Native stop can resolve the speech future successfully. Claim the
        // terminal outcome first so that completion cannot turn a timeout into
        // a successful question and reopen capture during cleanup.
        timedOut = true;
        try {
          // A small number of iOS AVSpeechSynthesizer route transitions do not
          // deliver didFinish. Stop the stale utterance so the H20 mic can
          // still open instead of leaving the child on a frozen screen.
          await _prompt.stop();
        } catch (_) {
          // Still resolve the bounded wait if native cleanup fails.
        } finally {
          if (!waiter.isCompleted) {
            final tolerateMissingIosCompletion =
                allowIosCompletionCallbackTimeout &&
                !kIsWeb &&
                defaultTargetPlatform == TargetPlatform.iOS;
            if (tolerateMissingIosCompletion) {
              waiter.complete();
            } else {
              // A timeout while playing the authored question is not proof
              // that the child heard it. Treat it as a playback failure so
              // capture never opens after a silent prompt.
              waiter.completeError(
                TimeoutException('Challenge prompt did not finish'),
              );
            }
          }
        }
      }());
    });

    try {
      await waiter.future;
    } finally {
      if (identical(_promptCompletionWaiter, waiter)) {
        _promptCompletionTimer?.cancel();
        _promptCompletionTimer = null;
        _promptCompletionWaiter = null;
      }
    }
  }

  Future<void> _startRecording() async {
    if (_pausedForMainAssistant ||
        _pausedAfterNoResponse ||
        _recording ||
        _busy ||
        _playingPrompt ||
        !mounted) {
      return;
    }
    final expected = _expectedEnglish;
    if (expected.isEmpty) return;
    final request = _request;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _prompt.stop();
      if (!mounted || _pausedForMainAssistant || request != _request) return;
      final prompt = _voicePromptService;
      final cueBeforeStart =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android);
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          prompt is SpeechReadyCuePlayer) {
        await _prepareSelectedLessonOutputWithRetry(request);
        if (!mounted || _pausedForMainAssistant || request != _request) return;
      }
      if (cueBeforeStart && prompt is SpeechReadyCuePlayer) {
        await (prompt as SpeechReadyCuePlayer).playSpeechReadyCue();
      }
      if (!mounted || _pausedForMainAssistant || request != _request) return;
      var usesIosSpeech = false;
      final iosSpeechInput = _usesIosOnDeviceRecognition
          ? widget.iosSpeechInput
          : null;
      if (iosSpeechInput != null) {
        if (iosSpeechInput is IOSStreamingSpeechInput) {
          _activeAttemptAudioPath = await widget.mediaService.recordingPath(
            lessonId: '${widget.lesson.id}-challenge',
            sentenceNumber: _recordingNumber,
            extension: 'wav',
          );
        } else {
          _activeAttemptAudioPath = null;
        }
        if (!mounted || _pausedForMainAssistant || request != _request) return;
        // Publish capture ownership before awaiting native start so MAIN/Back
        // can cancel route preparation, not just an already-open microphone.
        _recordingStartPending = true;
        _recordingUsesIosSpeech = true;
        usesIosSpeech = true;
        if (iosSpeechInput is IOSStreamingSpeechInput) {
          await iosSpeechInput
              .startLessonEnglishRecognitionWithRecording(
                _activeAttemptAudioPath!,
              )
              .timeout(const Duration(seconds: 8));
        } else {
          await iosSpeechInput.startLessonEnglishRecognition().timeout(
            const Duration(seconds: 8),
          );
        }
        if (!mounted || _pausedForMainAssistant || request != _request) return;
        // The selected iOS policy is on-device scoring. A native failure must
        // never silently start a second recorder and upload the child's audio.
        widget.mediaService.handoffSelectedLessonOutputToNativeCapture();
      }
      if (!usesIosSpeech) {
        _activeAttemptAudioPath = null;
        _recordingStartPending = true;
        await widget.mediaService
            .startRecording(
              lessonId: widget.lesson.id,
              sentenceNumber: _recordingNumber,
              lessonTitle: widget.lesson.titleVi,
              sentenceId: _attemptId,
              english: expected,
              vietnamese: _expectedVietnamese,
              saveToHistory: false,
            )
            .timeout(const Duration(seconds: 8));
      }
      if (!mounted || _pausedForMainAssistant || request != _request) {
        // The owner that invalidated a native start already cancelled it.
        // Cancelling here could kill a newer MAIN turn on the shared engine.
        if (!usesIosSpeech) {
          await widget.mediaService.cancelRecording().catchError((Object _) {});
        }
        return;
      }
      if (!cueBeforeStart && prompt is SpeechReadyCuePlayer) {
        await (prompt as SpeechReadyCuePlayer).playSpeechReadyCue();
      }
      if (!mounted || _pausedForMainAssistant || request != _request) return;
      setState(() {
        _recording = true;
        _recordingStartPending = false;
        _recordingUsesIosSpeech = usesIosSpeech;
        _busy = false;
      });
      final streamingIosSpeechInput = iosSpeechInput is StreamingSpeechInput
          ? iosSpeechInput as StreamingSpeechInput
          : null;
      final amplitudeDbfs = usesIosSpeech
          ? streamingIosSpeechInput?.amplitudeDbfs
          : widget.mediaService.recordingAmplitudeDbfs;
      _recordingEndpointDetector.start(
        amplitudeDbfs: amplitudeDbfs,
        onEndpoint: (_) {
          if (mounted && _recording) unawaited(_stopRecording());
        },
      );
    } catch (error) {
      if (!mounted || _pausedForMainAssistant || request != _request) return;
      _recordingEndpointDetector.cancel();
      if (_recordingUsesIosSpeech) {
        await widget.iosSpeechInput?.cancel().catchError((Object _) {});
        if (!mounted || _pausedForMainAssistant || request != _request) return;
      } else if (_recordingStartPending) {
        await widget.mediaService.cancelRecording().catchError((Object _) {});
        if (!mounted || _pausedForMainAssistant || request != _request) return;
      }
      setState(() {
        _recordingStartPending = false;
        _recordingUsesIosSpeech = false;
        _busy = false;
        _message = _friendlyError(error);
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _busy || !mounted) return;
    final request = _request;
    final pauseGeneration = _mainPauseGeneration;
    _recordingEndpointDetector.cancel();
    setState(() => _busy = true);
    var shouldOpenMicrophoneAgain = false;
    try {
      final usesIosSpeech = _recordingUsesIosSpeech;
      final LessonAttemptOutcome outcome;
      LessonRecording? completedRecording;
      final evaluatedAttemptNumber = _attemptNumber + 1;
      if (usesIosSpeech) {
        final result = await _stopAndScoreIosOnDevice(request);
        outcome = result.$1;
        completedRecording = result.$2;
      } else {
        final recording = await widget.mediaService.stopRecording();
        completedRecording = recording;
        if (!mounted || _pausedForMainAssistant || request != _request) {
          return;
        }
        setState(() {
          _recording = false;
          _recordingUsesIosSpeech = false;
        });
        LessonAttemptOutcome? evaluatedOutcome;
        await Future.wait<void>(<Future<void>>[
          _playAttemptRecordingToCompletion(recording),
          _attemptEvaluator
              .evaluate(
                lessonCode: widget.lesson.code,
                sentenceId: _attemptId,
                expectedEnglish: _expectedEnglish,
                recordingPath: recording.filePath,
                recordingDuration: recording.duration,
                attemptNumber: evaluatedAttemptNumber,
                childAge: widget.startAge,
                acceptedVariants: _acceptedRecognitionVariants,
                requireAllExpectedTokens: false,
              )
              .then<void>((value) => evaluatedOutcome = value),
        ]);
        if (!mounted || _pausedForMainAssistant || request != _request) {
          return;
        }
        outcome = evaluatedOutcome!;
      }
      if (!mounted || _pausedForMainAssistant || request != _request) return;
      if (usesIosSpeech && completedRecording != null) {
        setState(() {
          _recording = false;
          _recordingUsesIosSpeech = false;
        });
        await _playAttemptRecordingToCompletion(completedRecording);
        if (!mounted || _pausedForMainAssistant || request != _request) return;
      }
      if (outcome != LessonAttemptOutcome.unclear &&
          outcome != LessonAttemptOutcome.noResponse) {
        _attemptNumber = evaluatedAttemptNumber;
      }
      setState(() {
        _recording = false;
        _recordingUsesIosSpeech = false;
      });
      shouldOpenMicrophoneAgain = await _applyOutcome(outcome);
    } catch (error) {
      if (!mounted || _pausedForMainAssistant || request != _request) return;
      setState(() {
        _recording = false;
        _recordingUsesIosSpeech = false;
        _message = _friendlyError(error);
      });
    } finally {
      if (mounted && pauseGeneration == _mainPauseGeneration) {
        setState(() => _busy = false);
      }
    }
    // `_advance` has already finished the next coach prompt by this point.
    // Wait until the scoring state is released before claiming the H20 route;
    // otherwise the second challenge silently leaves its microphone closed.
    if (shouldOpenMicrophoneAgain &&
        mounted &&
        pauseGeneration == _mainPauseGeneration &&
        !_pausedForMainAssistant &&
        !_recording) {
      await _startRecording();
    }
  }

  Future<void> _playAttemptRecordingToCompletion(
    LessonRecording recording,
  ) async {
    final parsed = Uri.tryParse(recording.filePath);
    final uri = parsed != null && parsed.hasScheme
        ? parsed
        : Uri.file(recording.filePath);
    final requestedTimeout = recording.duration + const Duration(seconds: 5);
    final timeout = requestedTimeout < const Duration(seconds: 10)
        ? const Duration(seconds: 10)
        : requestedTimeout;
    try {
      await widget.mediaService.playToCompletion(
        uri,
        timeout: timeout,
        playbackGainDb: lessonRecordingPlaybackGainDb,
      );
    } catch (error) {
      // A playback problem must not discard the answer or prevent scoring.
      debugPrint('HOMI challenge attempt playback failed: $error');
    }
  }

  Future<(LessonAttemptOutcome, LessonRecording?)> _stopAndScoreIosOnDevice(
    int request,
  ) async {
    final speechInput = widget.iosSpeechInput;
    if (speechInput == null) return (LessonAttemptOutcome.unclear, null);
    final expectedEnglish = _expectedEnglish;
    final acceptedVariants = _acceptedRecognitionVariants;
    bool isCurrent() =>
        mounted && !_pausedForMainAssistant && request == _request;
    try {
      final capture = await speechInput.stop();
      if (!isCurrent()) return (LessonAttemptOutcome.unclear, null);
      final recordedAudio = capture.recordedAudio;
      final recording = recordedAudio == null
          ? null
          : LessonRecording(
              filePath: recordedAudio.filePath,
              duration: recordedAudio.duration,
            );
      final outcome = evaluateNativeLessonTranscripts(
        expectedEnglish: expectedEnglish,
        transcripts: <String>[capture.sourceText, ...capture.alternatives],
        acceptedVariants: acceptedVariants,
      );
      return (outcome, recording);
    } on StreamingSpeechInputException catch (error) {
      if (!isCurrent()) return (LessonAttemptOutcome.unclear, null);
      final recordedAudio = speechInput is IOSStreamingSpeechInput
          ? speechInput.takeLessonRecordingAudioCapture()
          : null;
      final recording = recordedAudio == null
          ? null
          : LessonRecording(
              filePath: recordedAudio.filePath,
              duration: recordedAudio.duration,
            );
      debugPrint(
        'HOMI iOS challenge recognition returned no usable speech: '
        'code=${error.code ?? 'unknown'}',
      );
      return (nativeLessonRecognitionFailureOutcome(error.code), recording);
    } catch (error) {
      debugPrint('HOMI iOS challenge recognition failed locally: $error');
      return (LessonAttemptOutcome.unclear, null);
    }
  }

  Future<bool> _applyOutcome(LessonAttemptOutcome outcome) async {
    final request = _request;
    bool isCurrent() =>
        mounted && !_pausedForMainAssistant && request == _request;
    if (outcome == LessonAttemptOutcome.good) {
      _invalidResponseCount = 0;
      await _speakFeedback(LessonFeedbackKind.correct);
      if (!isCurrent()) return false;
      await _notifyChallengeResolved(correct: true);
      if (!isCurrent()) return false;
      return _advance();
    }
    if (outcome == LessonAttemptOutcome.unclear) {
      if (!_acceptInvalidResponseOrPause()) return false;
      await _speakFeedback(LessonFeedbackKind.asr);
      return isCurrent();
    }
    if (outcome == LessonAttemptOutcome.noResponse) {
      if (!_acceptInvalidResponseOrPause()) return false;
      await _speakFeedback(LessonFeedbackKind.noResponse);
      return isCurrent();
    }
    _invalidResponseCount = 0;
    if (_attemptNumber >= 2) {
      return _giveAnswerAndAdvance(skip: false);
    }
    await _speakFeedback(LessonFeedbackKind.retry);
    if (!isCurrent()) return false;
    // Challenge retries repeat the authored question (including its choices),
    // not the correct answer used by the Core imitation flow.
    return _playCurrentPrompt(allowBusy: true, openMicrophone: false);
  }

  bool _acceptInvalidResponseOrPause() {
    if (!mounted || _pausedForMainAssistant) return false;
    _invalidResponseCount += 1;
    // Open one complete retry window. A second unusable result pauses directly
    // and must not be preceded by another invitation to speak.
    if (_invalidResponseCount < 2) return true;
    setState(() {
      _pausedAfterNoResponse = true;
      _message = 'Mình tạm dừng nhé.';
    });
    unawaited(
      _speakPromptAndWait(
        'Mình tạm dừng nhé.',
        audioKey: MainAssistantAudioKeys.cancelled,
      ),
    );
    return false;
  }

  Future<void> _resumeAfterNoResponse() async {
    if (!mounted) return;
    setState(() {
      _pausedAfterNoResponse = false;
      _invalidResponseCount = 0;
      _attemptNumber = 0;
      _message = null;
    });
    await _playCurrentPrompt(announceResume: true);
  }

  Future<void> _notifyChallengeResolved({required bool correct}) async {
    final callback = widget.onChallengeResolved;
    if (callback == null) return;
    await callback(_challenge, correct);
  }

  Future<void> _speakFeedback(LessonFeedbackKind kind) async {
    final request = _request;
    final (:message, :audioKey) = _challengeFeedback(kind);
    if (mounted) setState(() => _message = message);
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
      if (!mounted || _pausedForMainAssistant || request != _request) return;
      await _speakPromptAndWait(message, audioKey: audioKey);
    } catch (_) {
      // The written feedback remains visible; recording still resumes so a
      // temporary TTS outage never forces the child to use the phone.
    }
  }

  Future<bool> _giveAnswerAndAdvance({required bool skip}) async {
    final request = _request;
    bool isCurrent() =>
        mounted && !_pausedForMainAssistant && request == _request;
    if (skip) {
      await _speakFeedback(LessonFeedbackKind.skip);
    } else {
      await _speakFeedback(LessonFeedbackKind.give);
    }
    if (!isCurrent()) return false;
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
      if (!isCurrent()) return false;
      await _speakPromptAndWait(
        _expectedEnglish,
        locale: 'en-US',
        audioKey: ListeningAudioKeys.challengeAnswer(_challenge.id),
      );
    } catch (_) {
      // The written answer remains visible in the authored card.
    }
    if (!isCurrent()) return false;
    if (!skip) {
      await _saveNeedsPractice();
      if (!isCurrent()) return false;
      await _notifyChallengeResolved(correct: false);
      if (!isCurrent()) return false;
    }
    return _advance();
  }

  Future<void> _saveNeedsPractice() async {
    final callback = widget.onNeedsPractice;
    if (callback == null) return;
    final stableId = 'challenge:${_challengeIndex + 1}';
    try {
      await callback(stableId, _expectedEnglish, _expectedVietnamese);
    } catch (_) {
      // Vocabulary persistence must never interrupt the authored lesson.
    }
  }

  Future<bool> _advance() async {
    if (_pausedForMainAssistant) return false;
    if (_challengeIndex < widget.challenges.length - 1) {
      setState(() {
        _challengeIndex += 1;
        _attemptNumber = 0;
        _message = null;
      });
      return _playCurrentPrompt(allowBusy: true, openMicrophone: false);
    }
    await _speakPromptAndWait(
      'Bạn đã hoàn thành phần thử thách rồi.',
      audioKey: ListeningAudioKeys.feedbackCompleted,
    );
    if (!mounted || _pausedForMainAssistant) return false;
    if (mounted) Navigator.of(context).pop(true);
    return false;
  }

  ({String message, String? audioKey}) _challengeFeedback(
    LessonFeedbackKind kind,
  ) => switch (kind) {
    LessonFeedbackKind.correct => (
      message: 'Đúng rồi!',
      audioKey: ListeningAudioKeys.feedbackCorrect,
    ),
    LessonFeedbackKind.retry ||
    LessonFeedbackKind.noResponse ||
    LessonFeedbackKind.asr => (
      message: 'Bạn thử lại nhé.',
      audioKey: ListeningAudioKeys.feedbackTryAgain,
    ),
    LessonFeedbackKind.give => (
      message: 'Chưa đúng. Mình nghe câu đúng nhé.',
      audioKey: ListeningAudioKeys.feedbackIncorrect,
    ),
    LessonFeedbackKind.skip => (
      message: 'Được. Nghe câu đúng nhé.',
      audioKey: MainAssistantAudioKeys.challengeSkipCorrect,
    ),
  };

  String get _expectedEnglish => _challenge.correctAnswer;

  String get _expectedVietnamese => _challenge.correctVietnamese;

  Iterable<String> get _acceptedRecognitionVariants {
    for (final sentence in widget.lesson.sentences) {
      if (sentence.id == _challenge.targetId) {
        return sentence.recognitionVariants;
      }
    }
    return const <String>[];
  }

  String get _attemptId => _challenge.id;

  int get _recordingNumber => 100 + _challengeIndex + 1;

  String _friendlyError(Object error) {
    if (error is StreamingSpeechInputException) {
      return error.message;
    }
    final text = error.toString();
    if (text.contains('micro') || text.contains('Micro')) {
      return 'Ứng dụng cần quyền micro để nghe câu trả lời.';
    }
    return 'Chưa chấm được câu trả lời. Bạn thử nói lại nhé.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalSteps = widget.challenges.length;
    final currentStep = _challengeIndex;
    final progress = totalSteps == 0 ? 0.0 : (currentStep / totalSteps);

    return DisplayLanguageScope(
      language: widget.language,
      child: PopScope<bool>(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            unawaited(pauseForMainAssistant().catchError((Object _) {}));
          }
        },
        child: Scaffold(
          key: const Key('lesson-challenge-screen'),
          backgroundColor: Colors.transparent,
          body: LearningScenery(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.arrow_back_rounded),
                          tooltip: 'Quay lại',
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LinearProgressIndicator(value: progress),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _playingPrompt || _busy
                              ? null
                              : _replayCurrent,
                          icon: const Icon(Icons.volume_up_rounded),
                          tooltip: 'Nghe lại',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 132,
                      child: Image.asset(
                        MascotAssets.listen,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Thử thách nghe',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Câu ${_challengeIndex + 1}/${widget.challenges.length}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _ChallengeCard(challenge: _challenge),
                      ),
                    ),
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        FilledButton(
                          key: const Key('lesson-challenge-record-button'),
                          onPressed:
                              _busy || _playingPrompt || _pausedAfterNoResponse
                              ? null
                              : (_recording ? _stopRecording : _startRecording),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(64),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                HomiUi.controlRadius,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              if (_recording || _busy)
                                HomiWaveform(
                                  active: true,
                                  width: 48,
                                  height: 24,
                                  color: theme.colorScheme.onPrimary,
                                )
                              else
                                const Icon(Icons.mic_rounded, size: 28),
                              const SizedBox(width: 10),
                              Text(
                                _recording ? 'Dừng và chấm' : 'Nói câu trả lời',
                              ),
                            ],
                          ),
                        ),
                        if (_pausedAfterNoResponse) ...<Widget>[
                          const SizedBox(height: 10),
                          FilledButton.tonalIcon(
                            key: const Key(
                              'challenge-resume-after-no-response',
                            ),
                            onPressed: _resumeAfterNoResponse,
                            icon: const Icon(Icons.mic_rounded),
                            label: const Text('Thử lại mic'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.challenge});

  final ListeningChallengeContent challenge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return HomiSurface(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const HomiSectionHeading(
            icon: Icons.headphones_rounded,
            title: 'Nghe và trả lời',
          ),
          const SizedBox(height: 12),
          Text(challenge.prompt, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 18),
          for (final choice in challenge.choices) ...<Widget>[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surfaceContainerHighest
                    : AppColors.lavenderSoft,
                borderRadius: BorderRadius.circular(HomiUi.controlRadius),
              ),
              child: Text(choice, style: theme.textTheme.titleMedium),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Hãy nói đáp án bằng tiếng Anh, không nói A hoặc B.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
