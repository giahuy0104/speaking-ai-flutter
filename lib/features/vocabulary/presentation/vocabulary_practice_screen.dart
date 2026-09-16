import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/audio/learning_audio_dependencies.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../l10n/display_language.dart';
import '../../listening/application/lesson_attempt_evaluator.dart';
import '../../listening/application/lesson_media_service.dart';
import '../../listening/application/lesson_recording_endpoint_detector.dart';
import '../../listening/domain/lesson_guide_flow.dart';
import '../application/vocabulary_audio_service.dart';
import '../application/vocabulary_fixed_prompt_audio_service.dart';
import '../data/vocabulary_session_store.dart';
import '../data/vocabulary_store.dart';
import '../domain/vocabulary_entry.dart';
import '../domain/vocabulary_flow_v3.dart';

enum VocabularyPracticeResult {
  continueLearning,
  otherContent,
  parentAdded,
  stars,
}

class VocabularyPracticeScreen extends StatefulWidget {
  const VocabularyPracticeScreen({
    required this.language,
    required this.childAge,
    required this.session,
    required this.store,
    required this.sessionStore,
    required this.mediaService,
    this.audioDependencies,
    this.attemptEvaluator,
    this.recordingEndpointDetector,
    this.voicePromptService,
    this.vocabularyAudioService,
    this.fixedPromptAudioService,
    this.samplePause = const Duration(seconds: 2),
    this.autoStart = true,
    this.announceIntro = true,
    this.announceResume = false,
    this.onRequestVoiceChoice,
    super.key,
  });

  final DisplayLanguage language;
  final int childAge;
  final VocabularyPracticeSession session;
  final VocabularyStore store;
  final VocabularySessionStore sessionStore;
  final LessonMediaService mediaService;
  final LearningAudioDependencies? audioDependencies;
  final LessonAttemptEvaluator? attemptEvaluator;
  final LessonRecordingEndpointDetector? recordingEndpointDetector;
  final VoicePromptService? voicePromptService;
  final VocabularyContentAudioService? vocabularyAudioService;
  final VocabularyFixedPromptAudioService? fixedPromptAudioService;
  final Duration samplePause;
  final bool autoStart;
  final bool announceIntro;
  final bool announceResume;
  final Future<void> Function({
    String? noSpeechRetryPrompt,
    String? noSpeechExitPrompt,
  })?
  onRequestVoiceChoice;

  @override
  State<VocabularyPracticeScreen> createState() =>
      _VocabularyPracticeScreenState();
}

class _VocabularyPracticeScreenState extends State<VocabularyPracticeScreen>
    implements ActiveLearningModuleController {
  late VocabularyPracticeSession _session;
  late final LessonAttemptEvaluator _attemptEvaluator;
  late final bool _ownsAttemptEvaluator;
  late final VoicePromptService _voicePromptService;
  late final bool _ownsVoicePromptService;
  List<VocabularyEntry> _entries = const <VocabularyEntry>[];
  int _index = 0;
  int _attemptNumber = 1;
  int _cueCursor = 0;
  int _generation = 0;
  bool _loading = true;
  bool _busy = false;
  bool _recording = false;
  bool _paused = false;
  bool _pausedAfterNoResponse = false;
  bool _completed = false;
  bool _reviewHasMore = true;
  int _invalidResponseCount = 0;
  late bool _resumeAnnouncementPending;
  String _message = '';
  late final LessonRecordingEndpointDetector _recordingEndpointDetector;
  ActiveLearningModuleRegistry? _activeRegistry;
  Object? _activeRegistration;

  VocabularyEntry get _entry => _entries[_index];

  IOSStreamingSpeechInput? get _iosSpeechInput =>
      widget.audioDependencies?.learningSpeechInput is IOSStreamingSpeechInput
      ? widget.audioDependencies!.learningSpeechInput as IOSStreamingSpeechInput
      : null;

  bool get _usesIosNativeRecognition =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      _ownsAttemptEvaluator &&
      _iosSpeechInput != null;

  String get _recordingLessonId =>
      'vocabulary_${_session.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';

  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.vocabulary;

  @override
  bool get isPausedForMain => _paused;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _resumeAnnouncementPending = widget.announceResume;
    _ownsAttemptEvaluator = widget.attemptEvaluator == null;
    _attemptEvaluator =
        widget.attemptEvaluator ?? createDefaultLessonAttemptEvaluator();
    _recordingEndpointDetector =
        widget.recordingEndpointDetector ?? LessonRecordingEndpointDetector();
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService =
        widget.voicePromptService ??
        createVoicePromptService(
          coordinator: widget.audioDependencies?.audioTurnCoordinator,
          owner: AudioTurnOwner.vocabulary,
        );
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = ActiveLearningModuleScope.maybeOf(context);
    if (identical(registry, _activeRegistry)) {
      return;
    }
    if (_activeRegistry != null && _activeRegistration != null) {
      _activeRegistry!.unregister(_activeRegistration!);
    }
    _activeRegistry = registry;
    _activeRegistration = registry?.register(this);
  }

  @override
  void dispose() {
    _generation += 1;
    _recordingEndpointDetector.cancel();
    if (_activeRegistry != null && _activeRegistration != null) {
      _activeRegistry!.unregister(_activeRegistration!);
    }
    if (_recording) {
      if (_usesIosNativeRecognition) {
        unawaited(_iosSpeechInput!.cancel());
      } else {
        unawaited(widget.mediaService.cancelRecording());
      }
    }
    unawaited(widget.mediaService.stopPlayback());
    if (_ownsVoicePromptService) {
      unawaited(_voicePromptService.dispose());
    } else {
      unawaited(_voicePromptService.stop());
    }
    if (_ownsAttemptEvaluator &&
        _attemptEvaluator is DisposableLessonAttemptEvaluator) {
      (_attemptEvaluator as DisposableLessonAttemptEvaluator).dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final all = await widget.store.read();
    final byId = <String, VocabularyEntry>{
      for (final entry in all) entry.id: entry,
    };
    final entries = widget.session.entryIds
        .map((id) => byId[id])
        .whereType<VocabularyEntry>()
        .toList(growable: false);
    if (!mounted) {
      return;
    }
    if (entries.isEmpty) {
      await widget.sessionStore.clearActive();
      if (mounted) {
        Navigator.of(context).pop(VocabularyPracticeResult.otherContent);
      }
      return;
    }
    setState(() {
      _entries = entries;
      _index = widget.session.currentIndex.clamp(0, entries.length - 1);
      _cueCursor = _index;
      _loading = false;
      _message = _isToday
          ? VocabularyFlowV3.todayIntro
          : VocabularyFlowV3.reviewIntro;
    });
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_startCurrent(includeIntro: widget.announceIntro));
        }
      });
    }
  }

  bool get _isToday => _session.mode == VocabularyPracticeMode.today;
  bool get _isReview => _session.mode == VocabularyPracticeMode.review;

  Future<void> _startCurrent({bool includeIntro = false}) async {
    if (!mounted ||
        _loading ||
        _completed ||
        _busy ||
        _recording ||
        _paused ||
        _pausedAfterNoResponse) {
      return;
    }
    final generation = ++_generation;
    final entry = _entry;
    final includeResume = !includeIntro && _resumeAnnouncementPending;
    _resumeAnnouncementPending = false;
    setState(() {
      _busy = true;
      _message = includeIntro
          ? (_isToday
                ? VocabularyFlowV3.todayIntro
                : VocabularyFlowV3.reviewIntro)
          : includeResume
          ? (_isToday
                ? VocabularyFlowV3.todayResume
                : VocabularyFlowV3.reviewResume)
          : _isToday
          ? 'Con nghe nhé.'
          : 'Con nghe kỹ rồi nói lại nhé.';
    });
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
      if (includeIntro) {
        await _speakAndWait(
          _isToday ? VocabularyFlowV3.todayIntro : VocabularyFlowV3.reviewIntro,
        );
      }
      if (includeResume) {
        await _speakAndWait(
          _isToday
              ? VocabularyFlowV3.todayResume
              : VocabularyFlowV3.reviewResume,
        );
      }
      if (!_isCurrent(generation, entry.id)) return;
      await _speakVocabularyText(entry, entry.word, locale: 'en-US');
      if (widget.samplePause > Duration.zero) {
        await Future<void>.delayed(widget.samplePause);
      }
      if (!_isCurrent(generation, entry.id)) return;
      await _speakVocabularyText(entry, entry.meaning, locale: 'vi-VN');
      if (!_isCurrent(generation, entry.id)) return;
      if (_isToday) {
        await widget.store.markTodayHeard(entry.id);
        if (!_isCurrent(generation, entry.id)) return;
        setState(() {
          _busy = false;
          _message = 'Đã nghe xong.';
        });
        await _advance();
        return;
      }
      final cue = LessonGuideFlowV2.coreSpeakCue(_cueCursor++);
      await _playLessonPrompt(cue);
      if (!_isCurrent(generation, entry.id)) return;
      setState(() => _busy = false);
      await _startRecording(generation: generation, entry: entry);
    } catch (error) {
      if (!_isCurrent(generation, entry.id)) return;
      setState(() {
        _busy = false;
        _message = _friendlyError(error);
      });
    }
  }

  Future<void> _startRecording({
    required int generation,
    required VocabularyEntry entry,
  }) async {
    if (!_isCurrent(generation, entry.id) ||
        _recording ||
        _pausedAfterNoResponse) {
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Đang mở micro…';
    });
    try {
      final cueBeforeStart =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      if (cueBeforeStart && _voicePromptService is SpeechReadyCuePlayer) {
        await (_voicePromptService as SpeechReadyCuePlayer)
            .playSpeechReadyCue();
      }
      if (!_isCurrent(generation, entry.id)) return;
      if (_usesIosNativeRecognition) {
        final path = await widget.mediaService.recordingPath(
          lessonId: _recordingLessonId,
          sentenceNumber: _index + 1,
          extension: 'wav',
        );
        await _iosSpeechInput!.startLessonEnglishRecognitionWithRecording(path);
      } else {
        await widget.mediaService.startRecording(
          lessonId: _recordingLessonId,
          sentenceNumber: _index + 1,
          lessonTitle: _isToday
              ? 'Danh sách hôm nay'
              : _isReview
              ? 'Luyện lại'
              : 'Nói lại',
          sentenceId: entry.id,
          english: entry.word,
          vietnamese: entry.meaning,
          saveToHistory: false,
        );
      }
      if (!_isCurrent(generation, entry.id)) {
        await _cancelCapture();
        return;
      }
      if (!cueBeforeStart && _voicePromptService is SpeechReadyCuePlayer) {
        await (_voicePromptService as SpeechReadyCuePlayer)
            .playSpeechReadyCue();
      }
      if (!_isCurrent(generation, entry.id)) return;
      setState(() {
        _recording = true;
        _busy = false;
        _message = 'Đến lượt bạn.';
      });
      _recordingEndpointDetector.start(
        amplitudeDbfs:
            _iosSpeechInput?.amplitudeDbfs ??
            widget.mediaService.recordingAmplitudeDbfs,
        onEndpoint: (_) {
          if (mounted && _recording && !_paused) {
            unawaited(_stopRecording());
          }
        },
      );
    } catch (error) {
      _recordingEndpointDetector.cancel();
      if (!_isCurrent(generation, entry.id)) return;
      setState(() {
        _recording = false;
        _busy = false;
        _message = _friendlyError(error);
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _busy || _paused) {
      return;
    }
    _recordingEndpointDetector.cancel();
    final generation = _generation;
    final entry = _entry;
    setState(() {
      _recording = false;
      _busy = true;
      _message = 'HOMI đang nghe lại…';
    });
    try {
      if (_usesIosNativeRecognition) {
        await _finishIosAttempt(generation: generation, entry: entry);
        return;
      }
      final recording = await widget.mediaService.stopRecording();
      if (!_isCurrent(generation, entry.id)) return;
      final outcome = await _attemptEvaluator.evaluate(
        lessonCode: _recordingLessonId,
        sentenceId: entry.id,
        expectedEnglish: entry.word,
        recordingPath: recording.filePath,
        recordingDuration: recording.duration,
        attemptNumber: _attemptNumber,
        childAge: widget.childAge,
        acceptedVariants: VocabularyFlowV3.acceptedVariantsFor(entry),
        requireAllExpectedTokens: false,
      );
      if (!_isCurrent(generation, entry.id)) return;
      await _applyOutcome(
        outcome,
        generation: generation,
        entry: entry,
        recordingPath: recording.filePath,
      );
    } catch (error) {
      if (!_isCurrent(generation, entry.id)) return;
      setState(() {
        _busy = false;
        _message = _friendlyError(error);
      });
    }
  }

  Future<void> _finishIosAttempt({
    required int generation,
    required VocabularyEntry entry,
  }) async {
    LessonAttemptOutcome outcome;
    String? recordingPath;
    try {
      final capture = await _iosSpeechInput!.stop();
      recordingPath = capture.recordedAudio?.filePath;
      final candidates = <String>{capture.sourceText, ...capture.alternatives};
      outcome =
          candidates.any(
            (candidate) => matchesRecognizedLessonEnglish(
              entry.word,
              candidate,
              acceptedVariants: VocabularyFlowV3.acceptedVariantsFor(entry),
              requireAllExpectedTokens: false,
            ),
          )
          ? LessonAttemptOutcome.good
          : LessonAttemptOutcome.retry;
    } on StreamingSpeechInputException {
      recordingPath = _iosSpeechInput!
          .takeLessonRecordingAudioCapture()
          ?.filePath;
      outcome = LessonAttemptOutcome.unclear;
    }
    if (!_isCurrent(generation, entry.id)) return;
    await _applyOutcome(
      outcome,
      generation: generation,
      entry: entry,
      recordingPath: recordingPath,
    );
  }

  Future<void> _applyOutcome(
    LessonAttemptOutcome outcome, {
    required int generation,
    required VocabularyEntry entry,
    String? recordingPath,
  }) async {
    switch (outcome) {
      case LessonAttemptOutcome.good:
        _invalidResponseCount = 0;
        final results = Map<String, bool>.of(_session.results)
          ..[entry.id] = true;
        final paths = Map<String, String>.of(_session.correctAudioPaths);
        if (recordingPath != null && recordingPath.isNotEmpty) {
          paths[entry.id] = recordingPath;
        }
        _session = _session.copyWith(
          results: results,
          correctAudioPaths: paths,
        );
        await widget.sessionStore.saveActive(_session);
        if (!_isCurrent(generation, entry.id)) return;
        final feedback = LessonAgeFeedbackLibrary.message(
          age: widget.childAge,
          kind: LessonFeedbackKind.correct,
        );
        setState(() => _message = feedback);
        await _playLessonPrompt(
          LessonGuidePrompt(audioCode: 'CORRECT', text: feedback),
        );
        if (!_isCurrent(generation, entry.id)) return;
        await _advance();
        return;
      case LessonAttemptOutcome.unclear:
        if (!await _acceptInvalidResponseOrPause(
          generation: generation,
          entry: entry,
        )) {
          return;
        }
        final feedback = LessonAgeFeedbackLibrary.message(
          age: widget.childAge,
          kind: LessonFeedbackKind.asr,
        );
        setState(() {
          _busy = false;
          _message = feedback;
        });
        await _playLessonPrompt(
          LessonGuidePrompt(audioCode: 'ASR', text: feedback),
        );
        if (!_isCurrent(generation, entry.id)) return;
        await _startRecording(generation: generation, entry: entry);
        return;
      case LessonAttemptOutcome.noResponse:
        if (!await _acceptInvalidResponseOrPause(
          generation: generation,
          entry: entry,
        )) {
          return;
        }
        final feedback = LessonAgeFeedbackLibrary.message(
          age: widget.childAge,
          kind: LessonFeedbackKind.noResponse,
        );
        setState(() {
          _busy = false;
          _message = feedback;
        });
        await _playLessonPrompt(
          LessonGuidePrompt(audioCode: 'NO_RESPONSE', text: feedback),
        );
        if (!_isCurrent(generation, entry.id)) return;
        await _startRecording(generation: generation, entry: entry);
        return;
      case LessonAttemptOutcome.retry:
      case LessonAttemptOutcome.needsPractice:
        _invalidResponseCount = 0;
        if (_attemptNumber < 2) {
          _attemptNumber = 2;
          setState(() {
            _busy = false;
            _message = LessonAgeFeedbackLibrary.message(
              age: widget.childAge,
              kind: LessonFeedbackKind.retry,
            );
          });
          await _playLessonPrompt(
            LessonGuidePrompt(audioCode: 'RETRY', text: _message),
          );
          if (!_isCurrent(generation, entry.id)) return;
          await _speakVocabularyText(entry, entry.word, locale: 'en-US');
          if (!_isCurrent(generation, entry.id)) return;
          await _startRecording(generation: generation, entry: entry);
          return;
        }
        await _recordNeedsPractice(entry, generation: generation);
        return;
    }
  }

  Future<bool> _acceptInvalidResponseOrPause({
    required int generation,
    required VocabularyEntry entry,
  }) async {
    _invalidResponseCount += 1;
    if (_invalidResponseCount < 2) return true;
    if (!_isCurrent(generation, entry.id)) return false;
    setState(() {
      _busy = false;
      _recording = false;
      _pausedAfterNoResponse = true;
      _message = VocabularyFlowV3.pauseAfterNoResponse;
    });
    await _speakAndWait(VocabularyFlowV3.pauseAfterNoResponse);
    return false;
  }

  Future<void> _resumeAfterNoResponse() async {
    if (!mounted || !_pausedAfterNoResponse) return;
    setState(() {
      _pausedAfterNoResponse = false;
      _invalidResponseCount = 0;
      _attemptNumber = 1;
      _message = VocabularyFlowV3.reviewResume;
    });
    await _startCurrent();
  }

  Future<void> _recordNeedsPractice(
    VocabularyEntry entry, {
    required int generation,
  }) async {
    final giveFeedback = LessonAgeFeedbackLibrary.message(
      age: widget.childAge,
      kind: LessonFeedbackKind.give,
    );
    setState(() => _message = giveFeedback);
    await _playLessonPrompt(
      LessonGuidePrompt(audioCode: 'GIVE', text: giveFeedback),
    );
    if (!_isCurrent(generation, entry.id)) return;
    await _speakAndWait(entry.word, locale: 'en-US');
    if (!_isCurrent(generation, entry.id)) return;
    final results = Map<String, bool>.of(_session.results);
    results.putIfAbsent(entry.id, () => false);
    _session = _session.copyWith(results: results);
    await widget.sessionStore.saveActive(_session);
    if (!_isCurrent(generation, entry.id)) return;
    await _advance();
  }

  Future<void> _advance() async {
    if (_index == _entries.length - 1) {
      var reviewHasMore = false;
      if (!_isToday) {
        await widget.store.commitPracticeResults(
          results: _session.results,
          correctAudioPaths: _session.correctAudioPaths,
        );
        await widget.sessionStore.completeReviewBlock(_session.entryIds);
        reviewHasMore = await widget.sessionStore.hasPendingReviewEntries(
          widget.store,
        );
        if (!reviewHasMore) {
          await widget.sessionStore.endReviewSession();
        }
      } else {
        await widget.sessionStore.clearActive();
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _recording = false;
        _completed = true;
        _reviewHasMore = reviewHasMore;
        _message = _isToday
            ? VocabularyFlowV3.todayCompletion
            : reviewHasMore
            ? VocabularyFlowV3.reviewGroupCompletion
            : VocabularyFlowV3.reviewCycleFinished;
      });
      await _speakAndWait(_message);
      await widget.onRequestVoiceChoice?.call(
        noSpeechRetryPrompt: _message,
        noSpeechExitPrompt: VocabularyFlowV3.pauseAfterNoResponse,
      );
      return;
    }
    final nextIndex = _index + 1;
    _session = _session.copyWith(currentIndex: nextIndex);
    await widget.sessionStore.saveActive(_session);
    if (!mounted) return;
    setState(() {
      _index = nextIndex;
      _attemptNumber = 1;
      _invalidResponseCount = 0;
      _pausedAfterNoResponse = false;
      _busy = false;
      _recording = false;
    });
    await _startCurrent();
  }

  bool _isCurrent(int generation, String entryId) =>
      mounted &&
      !_paused &&
      !_pausedAfterNoResponse &&
      !_completed &&
      generation == _generation &&
      _entry.id == entryId;

  Future<void> _cancelCapture() async {
    _recordingEndpointDetector.cancel();
    if (_usesIosNativeRecognition) {
      await _iosSpeechInput!.cancel().catchError((Object _) {});
    } else {
      await widget.mediaService.cancelRecording().catchError((Object _) {});
    }
  }

  @override
  Future<void> pauseForMainAssistant() async {
    if (_paused) return;
    _paused = true;
    _generation += 1;
    final wasRecording = _recording;
    _recording = false;
    _recordingEndpointDetector.cancel();
    if (mounted) {
      setState(() {
        _busy = false;
        _message = 'Hoạt động đang tạm dừng.';
      });
    }
    if (wasRecording) {
      await _cancelCapture();
    }
    await Future.wait<void>(<Future<void>>[
      widget.mediaService.stopPlayback().catchError((Object _) {}),
      _voicePromptService.stop().catchError((Object _) {}),
    ]);
  }

  Future<void> _resume({bool replay = true, bool announceResume = true}) async {
    if (!_paused || _completed) return;
    _paused = false;
    _pausedAfterNoResponse = false;
    _invalidResponseCount = 0;
    if (_isReview) _attemptNumber = 1;
    _resumeAnnouncementPending = announceResume;
    if (mounted) {
      setState(() => _message = 'Mình tiếp tục nhé.');
    }
    if (replay) {
      await _startCurrent();
    }
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    if (!mounted) {
      return const ActiveLearningCommandResult.unavailable();
    }
    if (_completed) {
      _paused = false;
      if (_isToday && command == ActiveLearningCommand.resume) {
        // MAIN resumes a paused owner automatically after a silent command
        // window. Completion is a waiting-for-choice state, not replay consent.
        setState(() => _message = VocabularyFlowV3.todayCompletion);
        return const ActiveLearningCommandResult.handled();
      }
      if (command == ActiveLearningCommand.vocabularyParentAdded) {
        _finish(VocabularyPracticeResult.parentAdded);
        return const ActiveLearningCommandResult.handled();
      }
      if (command == ActiveLearningCommand.vocabularyStars) {
        _finish(VocabularyPracticeResult.stars);
        return const ActiveLearningCommandResult.handled();
      }
      if (_isToday &&
          (command == ActiveLearningCommand.vocabularyPracticeAgain ||
              command == ActiveLearningCommand.restart ||
              command == ActiveLearningCommand.replayCurrent)) {
        _finish(VocabularyPracticeResult.continueLearning);
        return const ActiveLearningCommandResult.handled();
      }
      if ((command == ActiveLearningCommand.resume ||
              command == ActiveLearningCommand.nextItem) &&
          !_isToday &&
          _reviewHasMore) {
        _finish(VocabularyPracticeResult.continueLearning);
        return const ActiveLearningCommandResult.handled();
      }
      if (!_isToday &&
          !_reviewHasMore &&
          (command == ActiveLearningCommand.resume ||
              command == ActiveLearningCommand.nextItem)) {
        setState(() => _message = VocabularyFlowV3.reviewCycleFinished);
        return const ActiveLearningCommandResult.unavailable(
          spokenReply: VocabularyFlowV3.reviewCycleFinished,
        );
      }
      if (command == ActiveLearningCommand.exitToHome) {
        _finish(VocabularyPracticeResult.otherContent);
        return const ActiveLearningCommandResult.handled();
      }
      if (_isToday && command == ActiveLearningCommand.nextItem) {
        return const ActiveLearningCommandResult.unavailable(
          spokenReply: VocabularyFlowV3.todayCompletion,
        );
      }
    }
    switch (command) {
      case ActiveLearningCommand.stop:
        await pauseForMainAssistant();
        return const ActiveLearningCommandResult.handled(
          spokenReply: 'Đã dừng.',
        );
      case ActiveLearningCommand.resume:
        await _resume();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.replayCurrent:
        if (!_paused) await pauseForMainAssistant();
        await _resume(announceResume: false);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.previousItem:
        if (_isReview || _recording || _busy) {
          return const ActiveLearningCommandResult.unavailable();
        }
        final atFirst = _index == 0;
        _generation += 1;
        setState(() {
          _paused = false;
          if (!atFirst) _index -= 1;
          _attemptNumber = 1;
        });
        _session = _session.copyWith(currentIndex: _index);
        await widget.sessionStore.saveActive(_session);
        if (atFirst) {
          await _playLessonPrompt(
            const LessonGuidePrompt(
              audioCode: 'CORE_FIRST_PREVIOUS',
              text: 'Đây là câu đầu tiên. Mình nghe lại nhé.',
            ),
          );
        }
        await _startCurrent();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.exitToHome:
        if (!_completed) {
          return const ActiveLearningCommandResult.unavailable(
            spokenReply: VocabularyFlowV3.finishActiveGroupFirst,
          );
        }
        await pauseForMainAssistant();
        if (mounted) {
          Navigator.of(context).pop(VocabularyPracticeResult.otherContent);
        }
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.nextItem:
      case ActiveLearningCommand.nextLesson:
      case ActiveLearningCommand.previousLesson:
      case ActiveLearningCommand.restart:
      case ActiveLearningCommand.vocabularyParentAdded:
      case ActiveLearningCommand.vocabularyPracticeAgain:
      case ActiveLearningCommand.vocabularyStars:
      case ActiveLearningCommand.vocabularyLatest:
      case ActiveLearningCommand.vocabularyAll:
        return const ActiveLearningCommandResult.unavailable(
          spokenReply: 'Mình học xong lượt này trước nhé.',
        );
    }
  }

  void _finish(VocabularyPracticeResult result) {
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final screen = DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LearningScenery(
          overlayOpacity: 0.08,
          child: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            IconButton.filledTonal(
                              onPressed: () => unawaited(_exitPractice()),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            Expanded(
                              child: Text(
                                _isToday
                                    ? 'Danh sách hôm nay'
                                    : _isReview
                                    ? 'Luyện lại'
                                    : 'Nói lại',
                                textAlign: TextAlign.center,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 18),
                        LinearProgressIndicator(
                          value: _completed
                              ? 1
                              : (_index + 1) / _entries.length,
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${_completed ? _entries.length : _index + 1}/${_entries.length}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        if (!_completed) _buildEntryCard(context),
                        const SizedBox(height: 22),
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                        const SizedBox(height: 22),
                        if (_completed)
                          _buildCompletionActions(context)
                        else
                          _buildPracticeAction(context),
                        const Spacer(),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
    return PopScope<VocabularyPracticeResult>(
      canPop: !_isToday || _completed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exitPractice());
      },
      child: screen,
    );
  }

  Widget _buildEntryCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('vocabulary-practice-entry'),
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(32),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x24142451),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Text(
            _entry.word,
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(
              color: AppColors.indigoDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _entry.meaning,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildPracticeAction(BuildContext context) {
    if (_pausedAfterNoResponse) {
      return FilledButton.icon(
        key: const Key('vocabulary-resume-after-no-response'),
        onPressed: () => unawaited(_resumeAfterNoResponse()),
        icon: const Icon(Icons.mic_rounded),
        label: const Text('Thử lại mic'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(240, 58),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      );
    }
    final enabled = !_busy && !_paused;
    return FilledButton.icon(
      key: const Key('vocabulary-practice-main-action'),
      onPressed: !enabled
          ? null
          : _recording
          ? () => unawaited(_stopRecording())
          : () => unawaited(_startCurrent()),
      icon: Icon(
        _isToday
            ? Icons.play_arrow_rounded
            : _recording
            ? Icons.stop_rounded
            : Icons.mic_rounded,
      ),
      label: Text(
        _paused
            ? 'Đang tạm dừng'
            : _isToday
            ? 'Bắt đầu nghe'
            : _recording
            ? 'Con nói xong'
            : 'Nghe và nói lại',
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size(240, 58),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildCompletionActions(BuildContext context) {
    final canContinue = _isToday || _reviewHasMore;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              key: const Key('vocabulary-other-content'),
              onPressed: () => _finish(VocabularyPracticeResult.otherContent),
              child: const Text('Học nội dung khác'),
            ),
          ),
          if (canContinue) ...<Widget>[
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('vocabulary-continue-learning'),
                onPressed: () =>
                    _finish(VocabularyPracticeResult.continueLearning),
                child: Text(_isToday ? 'Học lại' : 'Học tiếp'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '');

  Future<void> _exitPractice() async {
    if (_isToday && !_completed) {
      await pauseForMainAssistant();
      _paused = false;
      if (mounted) {
        setState(() => _message = VocabularyFlowV3.finishActiveGroupFirst);
      }
      await _speakAndWait(VocabularyFlowV3.finishActiveGroupFirst);
      if (mounted) await _startCurrent();
      return;
    }
    await pauseForMainAssistant();
    if (mounted) {
      Navigator.of(context).pop(VocabularyPracticeResult.otherContent);
    }
  }

  Future<void> _speakAndWait(
    String text, {
    String locale = 'vi-VN',
    bool allowFixedPrompt = true,
  }) async {
    if (allowFixedPrompt &&
        locale.toLowerCase().startsWith('vi') &&
        await widget.fixedPromptAudioService?.playPromptIfAvailable(text) ==
            true) {
      return;
    }
    final promptService = _voicePromptService;
    if (!kIsWeb && promptService is SelectedMediaOutputVoicePromptService) {
      await (promptService as SelectedMediaOutputVoicePromptService)
          .speakAndWaitOnSelectedMediaOutput(text, locale: locale);
      return;
    }
    await promptService.speakAndWait(text, locale: locale);
  }

  Future<void> _playLessonPrompt(LessonGuidePrompt prompt) async {
    if (await widget.fixedPromptAudioService?.playAudioCodeIfAvailable(
          prompt.audioCode,
        ) ==
        true) {
      return;
    }
    await _speakAndWait(prompt.text, allowFixedPrompt: false);
  }

  Future<void> _speakVocabularyText(
    VocabularyEntry entry,
    String text, {
    required String locale,
  }) async {
    final audio = widget.vocabularyAudioService;
    if (entry.isParentAdded && audio != null) {
      await audio.speakAndWait(text, locale: locale);
      return;
    }
    await _speakAndWait(text, locale: locale, allowFixedPrompt: false);
  }
}
