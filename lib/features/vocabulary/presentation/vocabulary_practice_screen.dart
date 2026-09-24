import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../app/praise_fireworks.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/audio/learning_audio_dependencies.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../l10n/display_language.dart';
import '../../listening/application/lesson_attempt_evaluator.dart';
import '../../listening/application/lesson_media_service.dart';
import '../../listening/application/lesson_recording_endpoint_detector.dart';
import '../../listening/domain/lesson_guide_flow.dart';
import '../../voice_navigation/domain/master_navigation_contract.dart';
import '../application/vocabulary_audio_service.dart';
import '../application/vocabulary_fixed_prompt_audio_service.dart';
import '../data/vocabulary_session_store.dart';
import '../data/vocabulary_store.dart';
import '../domain/vocabulary_audio_keys.dart';
import '../domain/vocabulary_entry.dart';
import '../domain/vocabulary_flow_v3.dart';

const _practiceHomiSceneryAsset =
    'assets/images/vocabulary/practice-homi-background.png';

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
    implements ActiveLearningModuleController, ActiveLearningVoiceContext {
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
  bool _capturePending = false;
  bool _preparingRecording = false;
  bool _processingAttempt = false;
  bool _paused = false;
  bool _pausedAfterNoResponse = false;
  bool _completed = false;
  bool _todayEnViCompleted = false;
  bool _exiting = false;
  bool _reviewHasMore = true;
  bool _praiseFireworksVisible = false;
  int _invalidResponseCount = 0;
  int _praiseFireworksSequence = 0;
  Timer? _praiseFireworksTimer;
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
    _cancelPraiseFireworks();
    _recordingEndpointDetector.cancel();
    if (_activeRegistry != null && _activeRegistration != null) {
      _activeRegistry!.unregister(_activeRegistration!);
    }
    if (!_exiting && (_recording || _capturePending)) {
      if (_usesIosNativeRecognition) {
        unawaited(_iosSpeechInput!.cancel());
      } else {
        unawaited(widget.mediaService.cancelRecording());
      }
    }
    if (!_exiting) unawaited(widget.mediaService.stopPlayback());
    if (_ownsVoicePromptService) {
      unawaited(_voicePromptService.dispose());
    } else if (!_exiting) {
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
          : 'Bạn nghe kỹ rồi nói lại nhé.';
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

  @override
  ActiveLearningVoiceNode get mainVoiceNode => _completed
      ? (_isToday
            ? ActiveLearningVoiceNode.todayEnd
            : _reviewHasMore
            ? ActiveLearningVoiceNode.blockEnd
            : ActiveLearningVoiceNode.reviewAlternatives)
      : _isToday
      ? _todayEnViCompleted
            ? ActiveLearningVoiceNode.todayAfterEnVi
            : ActiveLearningVoiceNode.today
      : ActiveLearningVoiceNode.review;

  @override
  String get mainVoicePrompt => _completed
      ? (_isToday
            ? VocabularyFlowV3.todayCompletion
            : _reviewHasMore
            ? VocabularyFlowV3.reviewGroupCompletion
            : VocabularyFlowV3.reviewCycleFinished)
      : MasterNavigationContract.coreControlPrompt;
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
      if (_isToday) _todayEnViCompleted = false;
      _busy = true;
      _preparingRecording = false;
      _processingAttempt = false;
      _message = includeIntro
          ? (_isToday
                ? VocabularyFlowV3.todayIntro
                : VocabularyFlowV3.reviewIntro)
          : includeResume
          ? (_isToday
                ? VocabularyFlowV3.todayResume
                : VocabularyFlowV3.reviewResume)
          : _isToday
          ? 'Bạn nghe nhé.'
          : 'Bạn nghe kỹ rồi nói lại nhé.';
    });
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
      if (!_isCurrent(generation, entry.id)) return;
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
          _todayEnViCompleted = true;
          _busy = false;
          _message = 'Đã nghe xong.';
        });
        // FINAL T04 permits NEXT_ITEM only after the full EN + VI pair. Keep a
        // short MAIN command window, then continue automatically as before.
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (!_isCurrent(generation, entry.id)) return;
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
      _preparingRecording = true;
      _processingAttempt = false;
      _message = 'Đang mở micro…';
    });
    try {
      final android =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final cueBeforeStart =
          android || (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
      if (android) {
        // Keep the H20 output selected while the cue (and its acoustic tail)
        // finishes. Opening capture first records the cue as the child's voice.
        await widget.mediaService.prepareSelectedLessonOutput();
        if (!_isCurrent(generation, entry.id)) return;
      }
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
        if (!_isCurrent(generation, entry.id)) return;
        _capturePending = true;
        await _iosSpeechInput!.startLessonEnglishRecognitionWithRecording(path);
      } else {
        _capturePending = true;
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
        // MAIN/Back already cancelled this native turn. A late cancellation
        // here could stop the newer owner of the shared Apple Speech engine.
        if (!_usesIosNativeRecognition) await _cancelCapture();
        return;
      }
      if (!cueBeforeStart && _voicePromptService is SpeechReadyCuePlayer) {
        await (_voicePromptService as SpeechReadyCuePlayer)
            .playSpeechReadyCue();
      }
      if (!_isCurrent(generation, entry.id)) {
        if (!_usesIosNativeRecognition) await _cancelCapture();
        return;
      }
      setState(() {
        _recording = true;
        _capturePending = false;
        _preparingRecording = false;
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
        _capturePending = false;
        _preparingRecording = false;
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
    final mediaService = widget.mediaService;
    setState(() {
      _recording = false;
      _capturePending = true;
      _preparingRecording = false;
      _processingAttempt = true;
      _busy = true;
      _message = 'HOMI đang nghe lại…';
    });
    try {
      if (_usesIosNativeRecognition) {
        await _finishIosAttempt(
          generation: generation,
          entry: entry,
          mediaService: mediaService,
        );
        return;
      }
      final recording = await mediaService.stopRecording();
      var recordingDiscarded = false;
      try {
        if (!_isCurrent(generation, entry.id)) return;
        _capturePending = false;
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
        if (outcome != LessonAttemptOutcome.good) {
          await _deleteTemporaryRecording(mediaService, recording.filePath);
          recordingDiscarded = true;
        }
        await _applyOutcome(
          outcome,
          generation: generation,
          entry: entry,
          recordingPath: recording.filePath,
        );
      } finally {
        if (!recordingDiscarded) {
          await _discardUnretainedAttemptRecording(
            mediaService,
            entry,
            recording.filePath,
          );
        }
      }
    } catch (error) {
      if (!_isCurrent(generation, entry.id)) return;
      setState(() {
        _capturePending = false;
        _processingAttempt = false;
        _busy = false;
        _message = _friendlyError(error);
      });
    }
  }

  Future<void> _finishIosAttempt({
    required int generation,
    required VocabularyEntry entry,
    required LessonMediaService mediaService,
  }) async {
    LessonAttemptOutcome outcome;
    String? recordingPath;
    var recordingDiscarded = false;
    try {
      try {
        final capture = await _iosSpeechInput!.stop();
        recordingPath = capture.recordedAudio?.filePath;
        if (!_isCurrent(generation, entry.id)) return;
        _capturePending = false;
        outcome = evaluateNativeLessonTranscripts(
          expectedEnglish: entry.word,
          transcripts: <String>[capture.sourceText, ...capture.alternatives],
          acceptedVariants: VocabularyFlowV3.acceptedVariantsFor(entry),
        );
      } on StreamingSpeechInputException catch (error) {
        // A stale stop must not consume a newer MAIN/lesson turn's local WAV.
        if (!_isCurrent(generation, entry.id)) return;
        _capturePending = false;
        recordingPath = _iosSpeechInput!
            .takeLessonRecordingAudioCapture()
            ?.filePath;
        outcome = nativeLessonRecognitionFailureOutcome(error.code);
      }
      if (!_isCurrent(generation, entry.id)) return;
      if (outcome != LessonAttemptOutcome.good) {
        await _deleteTemporaryRecording(mediaService, recordingPath);
        recordingDiscarded = true;
      }
      await _applyOutcome(
        outcome,
        generation: generation,
        entry: entry,
        recordingPath: recordingPath,
      );
    } finally {
      if (!recordingDiscarded) {
        await _discardUnretainedAttemptRecording(
          mediaService,
          entry,
          recordingPath,
        );
      }
    }
  }

  Future<void> _discardUnretainedAttemptRecording(
    LessonMediaService mediaService,
    VocabularyEntry entry,
    String? recordingPath,
  ) async {
    final path = recordingPath?.trim();
    if (path == null ||
        path.isEmpty ||
        _session.correctAudioPaths[entry.id] == path) {
      return;
    }
    await _deleteTemporaryRecording(mediaService, path);
  }

  Future<void> _deleteTemporaryRecording(
    LessonMediaService mediaService,
    String? recordingPath,
  ) async {
    final path = recordingPath?.trim();
    if (path == null || path.isEmpty) return;
    try {
      await mediaService.deleteRecording(path);
    } catch (error) {
      debugPrint('HOMI Review temporary recording cleanup failed: $error');
    }
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
        _showPraiseFireworks();
        await _playLessonPrompt(
          LessonGuidePrompt(
            audioCode: 'CORRECT',
            text: feedback,
            audioKey: LessonAgeFeedbackLibrary.audioKeyFor(feedback),
            locale: LessonAgeFeedbackLibrary.localeFor(feedback),
          ),
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
        setState(() => _message = feedback);
        await _playLessonPrompt(
          LessonGuidePrompt(
            audioCode: 'ASR',
            text: feedback,
            audioKey: LessonAgeFeedbackLibrary.audioKeyFor(feedback),
            locale: LessonAgeFeedbackLibrary.localeFor(feedback),
          ),
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
        setState(() => _message = feedback);
        await _playLessonPrompt(
          LessonGuidePrompt(
            audioCode: 'NO_RESPONSE',
            text: feedback,
            audioKey: LessonAgeFeedbackLibrary.audioKeyFor(feedback),
            locale: LessonAgeFeedbackLibrary.localeFor(feedback),
          ),
        );
        if (!_isCurrent(generation, entry.id)) return;
        await _startRecording(generation: generation, entry: entry);
        return;
      case LessonAttemptOutcome.retry:
      case LessonAttemptOutcome.needsPractice:
        _invalidResponseCount = 0;
        if (_attemptNumber < 2) {
          _attemptNumber = 2;
          setState(
            () => _message = LessonAgeFeedbackLibrary.message(
              age: widget.childAge,
              kind: LessonFeedbackKind.retry,
            ),
          );
          await _playLessonPrompt(
            LessonGuidePrompt(
              audioCode: 'RETRY',
              text: _message,
              audioKey: LessonAgeFeedbackLibrary.audioKeyFor(_message),
              locale: LessonAgeFeedbackLibrary.localeFor(_message),
            ),
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
      LessonGuidePrompt(
        audioCode: 'GIVE',
        text: giveFeedback,
        audioKey: LessonAgeFeedbackLibrary.audioKeyFor(giveFeedback),
        locale: LessonAgeFeedbackLibrary.localeFor(giveFeedback),
      ),
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
      final completionGeneration = _generation;
      var reviewHasMore = false;
      if (!_isToday) {
        await widget.store.commitPracticeResults(
          results: _session.results,
          correctAudioPaths: _session.correctAudioPaths,
        );
        // MAIN can move between review items without answering them. Keep
        // skipped items pending; only evaluated items have been attempted.
        await widget.sessionStore.completeReviewBlock(_session.results.keys);
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
      if (!mounted ||
          _exiting ||
          _paused ||
          completionGeneration != _generation) {
        return;
      }
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
    _cancelPraiseFireworks();
    final fixedPrompt = widget.fixedPromptAudioService;
    if (fixedPrompt is CancellableVocabularyFixedPromptAudioService) {
      (fixedPrompt as CancellableVocabularyFixedPromptAudioService)
          .cancelPending();
    }
    final wasRecording = _recording || _capturePending;
    _recording = false;
    _capturePending = false;
    _recordingEndpointDetector.cancel();
    if (mounted) {
      setState(() {
        _busy = false;
        _preparingRecording = false;
        _processingAttempt = false;
        _message = 'Hoạt động đang tạm dừng.';
      });
    }
    if (wasRecording) {
      await _cancelCapture();
    }
    await Future.wait<void>(<Future<void>>[
      widget.mediaService.stopPlayback().catchError((Object _) {}),
      _voicePromptService.stop().catchError((Object _) {}),
      if (widget.vocabularyAudioService != null)
        widget.vocabularyAudioService!.stop().catchError((Object _) {}),
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

  Future<void> _navigatePracticeItem(int offset) async {
    if (!_paused) await pauseForMainAssistant();
    if (!mounted || _completed || _exiting) return;
    final target = (_index + offset).clamp(0, _entries.length - 1);
    final atBoundary = target == _index;
    final generation = ++_generation;
    setState(() {
      _index = target;
      _paused = false;
      _busy = true;
      _pausedAfterNoResponse = false;
      _invalidResponseCount = 0;
      _attemptNumber = 1;
      _resumeAnnouncementPending = false;
    });
    final entryId = _entry.id;
    try {
      _session = _session.copyWith(currentIndex: _index);
      await widget.sessionStore.saveActive(_session);
      if (!_isCurrent(generation, entryId)) return;
      if (atBoundary) {
        if (offset < 0) {
          await _playLessonPrompt(
            const LessonGuidePrompt(
              audioCode: 'CORE_FIRST_PREVIOUS',
              text: 'Đây là câu đầu tiên. Mình nghe lại nhé.',
            ),
          );
        } else {
          await _playLessonPrompt(LessonGuideFlowV2.lastItemComplete);
        }
        if (!_isCurrent(generation, entryId)) return;
      } else if (offset > 0) {
        await _speakAndWait(MasterNavigationContract.nextItemPrompt);
        if (!_isCurrent(generation, entryId)) return;
      }
      setState(() => _busy = false);
      await _startCurrent();
    } catch (error) {
      if (!_isCurrent(generation, entryId)) return;
      setState(() {
        _busy = false;
        _message = _friendlyError(error);
      });
    }
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    if (!mounted) {
      return const ActiveLearningCommandResult.unavailable();
    }
    if (_loading || _exiting) {
      return const ActiveLearningCommandResult.busy();
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
        unawaited(_resume());
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.replayCurrent:
        if (!_paused) await pauseForMainAssistant();
        unawaited(_resume(announceResume: false));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.previousItem:
        // A lesson turn can outlast MAIN's command-dispatch timeout. Transfer
        // ownership now; the generation-guarded turn reports its own failures.
        unawaited(_navigatePracticeItem(-1));
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
        if (_isReview && !_completed) {
          unawaited(_navigatePracticeItem(1));
          return const ActiveLearningCommandResult.handled();
        }
        if (_isToday && _todayEnViCompleted && !_completed) {
          if (_index < _entries.length - 1) {
            unawaited(_navigatePracticeItem(1));
          } else {
            _paused = false;
            _todayEnViCompleted = false;
            unawaited(_advance());
          }
          return const ActiveLearningCommandResult.handled();
        }
        return const ActiveLearningCommandResult.unavailable(
          spokenReply: 'Mình học xong lượt này trước nhé.',
        );
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

  void _showPraiseFireworks() {
    _praiseFireworksTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _praiseFireworksSequence += 1;
      _praiseFireworksVisible = true;
    });
    _praiseFireworksTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || !_praiseFireworksVisible) return;
      setState(() => _praiseFireworksVisible = false);
      _praiseFireworksTimer = null;
    });
  }

  void _cancelPraiseFireworks() {
    _praiseFireworksTimer?.cancel();
    _praiseFireworksTimer = null;
    _praiseFireworksVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    final screen = DisplayLanguageScope(
      language: widget.language,
      child: PopScope<VocabularyPracticeResult>(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _commitNavigationExit();
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LearningScenery(
            assetPath: _practiceHomiSceneryAsset,
            overlayOpacity: 0.08,
            child: Stack(
              children: <Widget>[
                SafeArea(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final compactHeight = constraints.maxHeight < 700;
                            return SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(
                                18,
                                compactHeight ? 8 : 12,
                                18,
                                20,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 560,
                                  ),
                                  child: Column(
                                    children: <Widget>[
                                      _buildPracticeHeader(context),
                                      SizedBox(height: compactHeight ? 10 : 14),
                                      _buildProgress(context),
                                      SizedBox(height: compactHeight ? 18 : 26),
                                      if (!_completed)
                                        _buildEntryCard(
                                          context,
                                          compactHeight: compactHeight,
                                        ),
                                      SizedBox(height: compactHeight ? 14 : 20),
                                      Text(
                                        _message,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                              fontSize: compactHeight ? 16 : 17,
                                              height: 1.25,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      SizedBox(height: compactHeight ? 14 : 20),
                                      if (_completed)
                                        _buildCompletionActions(context)
                                      else
                                        _buildPracticeAction(context),
                                      SizedBox(height: compactHeight ? 12 : 18),
                                      _buildHomiCoach(
                                        context,
                                        viewportHeight: constraints.maxHeight,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    key: const Key('vocabulary-review-fireworks-interaction'),
                    child: _praiseFireworksVisible
                        ? PraiseFireworks(
                            keyPrefix: 'vocabulary-review-fireworks',
                            key: ValueKey(_praiseFireworksSequence),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
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

  Widget _buildPracticeHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      children: <Widget>[
        IconButton.filledTonal(
          onPressed: () => unawaited(_exitPractice()),
          icon: const Icon(Icons.arrow_back_rounded, size: 24),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(46),
            maximumSize: const Size.square(46),
            backgroundColor: isDark
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.white.withValues(alpha: 0.9),
            foregroundColor: isDark
                ? theme.colorScheme.primary
                : AppColors.primaryNavy,
            side: BorderSide(
              color: isDark ? theme.colorScheme.outline : AppColors.mintBorder,
            ),
          ),
        ),
        Expanded(
          child: Text(
            _isToday
                ? 'Danh sách hôm nay'
                : _isReview
                ? 'Luyện lại'
                : 'Nói lại',
            textAlign: TextAlign.center,
            maxLines: 1,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: isDark ? theme.colorScheme.primary : AppColors.deepNavy,
              fontSize: MediaQuery.sizeOf(context).width <= 360 ? 25 : 28,
              height: 1.08,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.55,
            ),
          ),
        ),
        const SizedBox(width: 46),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _completed ? 1.0 : (_index + 1) / _entries.length;
    return Column(
      children: <Widget>[
        Container(
          key: const Key('vocabulary-practice-progress-count'),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.colorScheme.tertiary, width: 1.2),
          ),
          child: Text(
            '${_completed ? _entries.length : _index + 1}/${_entries.length}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: theme.brightness == Brightness.dark
                ? theme.colorScheme.surfaceContainerHighest
                : const Color(0xFFC9F4E8),
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.accentPink,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEntryCard(BuildContext context, {required bool compactHeight}) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('vocabulary-practice-entry'),
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: 520,
        minHeight: compactHeight ? 172 : 202,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 26,
        vertical: compactHeight ? 28 : 34,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.96)),
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
              fontSize: MediaQuery.sizeOf(context).width <= 360 ? 38 : 44,
              height: 1.08,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _entry.meaning,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: MediaQuery.sizeOf(context).width <= 360 ? 23 : 25,
              height: 1.18,
              fontWeight: FontWeight.w700,
            ),
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
        label: Text(widget.language.choose('Thử lại mic', '重试麦克风')),
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
            ? widget.language.choose('Đang tạm dừng', '暂停中')
            : _isToday
            ? widget.language.choose('Bắt đầu nghe', '开始播放')
            : _preparingRecording && _busy
            ? widget.language.choose('Đang chuẩn bị mic', '正在准备麦克风')
            : _processingAttempt && _busy
            ? widget.language.choose('Đang xử lý', '正在处理')
            : _busy
            ? widget.language.choose('Đang phát hướng dẫn', '正在播放引导')
            : _recording
            ? widget.language.choose('Chạm để kết thúc ghi âm', '点击结束录音')
            : widget.language.choose('Chạm để bắt đầu ghi âm', '点击开始录音'),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size(286, 58),
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.softNavy,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildHomiCoach(
    BuildContext context, {
    required double viewportHeight,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mascotSize = viewportHeight < 620
        ? 132.0
        : viewportHeight < 760
        ? 180.0
        : 232.0;
    final platformWidth = (mascotSize * 1.46).clamp(150.0, 258.0);
    final mascotAsset = _completed
        ? MascotAssets.wave
        : _recording
        ? MascotAssets.speak
        : MascotAssets.listen;

    return Semantics(
      image: true,
      label: _completed
          ? 'HOMI chúc mừng bạn'
          : _recording
          ? 'HOMI đang nghe bạn nói'
          : 'HOMI đang lắng nghe cùng bạn',
      child: SizedBox(
        key: const Key('vocabulary-practice-homi-stage'),
        width: double.infinity,
        height: mascotSize + 22,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            Container(
              key: const Key('vocabulary-practice-homi-platform'),
              width: platformWidth,
              height: mascotSize * 0.2,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.tertiaryContainer.withValues(
                        alpha: 0.72,
                      )
                    : const Color(0xFFD8FAF0).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isDark
                      ? theme.colorScheme.tertiary.withValues(alpha: 0.42)
                      : Colors.white.withValues(alpha: 0.9),
                  width: 1.2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primaryNavy.withValues(
                      alpha: isDark ? 0.22 : 0.1,
                    ),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 8,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                child: Image.asset(
                  mascotAsset,
                  key: ValueKey<String>(mascotAsset),
                  width: mascotSize,
                  height: mascotSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ],
        ),
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
    if (_exiting) return;
    _commitNavigationExit();
    if (mounted) Navigator.of(context).pop();
  }

  void _commitNavigationExit() {
    if (_exiting) return;
    _exiting = true;
    final fixedPrompt = widget.fixedPromptAudioService;
    if (fixedPrompt is CancellableVocabularyFixedPromptAudioService) {
      (fixedPrompt as CancellableVocabularyFixedPromptAudioService)
          .cancelPending();
    }
    _paused = true;
    _generation++;
    _recordingEndpointDetector.cancel();
    final wasRecording = _recording || _capturePending;
    _recording = false;
    _capturePending = false;
    // Invalidate first, then release each owner independently. Neither native
    // stop nor checkpoint persistence may hold the navigation route hostage.
    for (final operation in <Future<void> Function()>[
      if (wasRecording) _cancelCapture,
      widget.mediaService.stopPlayback,
      _voicePromptService.stop,
      if (widget.vocabularyAudioService != null)
        widget.vocabularyAudioService!.stop,
      if (!_completed && !_loading)
        () => widget.sessionStore.saveActive(
          _session.copyWith(currentIndex: _index),
        ),
    ]) {
      unawaited(Future<void>.sync(operation).catchError((Object _) {}));
    }
  }

  Future<void> _speakAndWait(
    String text, {
    String locale = 'vi-VN',
    bool allowFixedPrompt = true,
  }) async {
    if (_exiting || !mounted) return;
    if (allowFixedPrompt &&
        locale.toLowerCase().startsWith('vi') &&
        await widget.fixedPromptAudioService?.playPromptIfAvailable(text) ==
            true) {
      return;
    }
    if (_exiting || !mounted) return;
    final promptService = _voicePromptService;
    if (!kIsWeb && promptService is SelectedMediaOutputVoicePromptService) {
      await widget.mediaService.prepareSelectedLessonOutput();
      if (_exiting || !mounted) return;
      await (promptService as SelectedMediaOutputVoicePromptService)
          .speakAndWaitOnSelectedMediaOutput(text, locale: locale);
      return;
    }
    await promptService.speakAndWait(text, locale: locale);
  }

  Future<void> _playLessonPrompt(LessonGuidePrompt prompt) async {
    final audioKey = prompt.audioKey;
    final voicePrompt = _voicePromptService;
    if (audioKey != null) {
      try {
        if (!kIsWeb &&
            voicePrompt is KeyedSelectedMediaOutputVoicePromptService) {
          await widget.mediaService.prepareSelectedLessonOutput();
          if (_exiting || !mounted) return;
          await (voicePrompt as KeyedSelectedMediaOutputVoicePromptService)
              .speakAndWaitOnSelectedMediaOutputWithAudioKey(
                audioKey,
                prompt.text,
                locale: prompt.locale,
              );
          return;
        }
        if (voicePrompt is KeyedVoicePromptService) {
          await (voicePrompt as KeyedVoicePromptService)
              .speakAndWaitWithAudioKey(
                audioKey,
                prompt.text,
                locale: prompt.locale,
              );
          return;
        }
      } catch (_) {
        if (_exiting || !mounted) return;
        // Keep the existing authored-code and TTS fallbacks below.
      }
    }
    if (await widget.fixedPromptAudioService?.playAudioCodeIfAvailable(
          prompt.audioCode,
        ) ==
        true) {
      return;
    }
    await _speakAndWait(
      prompt.text,
      locale: prompt.locale,
      allowFixedPrompt: false,
    );
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
    final audioKey = VocabularyAudioKeys.builtInEntry(entry, locale);
    final prompt = _voicePromptService;
    if (audioKey != null &&
        prompt is KeyedSelectedMediaOutputVoicePromptService) {
      await (prompt as KeyedSelectedMediaOutputVoicePromptService)
          .speakAndWaitOnSelectedMediaOutputWithAudioKey(
            audioKey,
            text,
            locale: locale,
          );
      return;
    }
    if (audioKey != null && prompt is KeyedVoicePromptService) {
      await (prompt as KeyedVoicePromptService).speakAndWaitWithAudioKey(
        audioKey,
        text,
        locale: locale,
      );
      return;
    }
    await _speakAndWait(text, locale: locale, allowFixedPrompt: false);
  }
}
