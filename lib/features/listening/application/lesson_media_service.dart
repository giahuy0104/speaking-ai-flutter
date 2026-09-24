import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../../core/audio/audio_input.dart';
import '../../../core/audio/audio_gain.dart';
import '../../../core/audio/audio_playback_service.dart';
import '../../../core/audio/audio_turn_coordinator.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../../../core/audio/hfp_audio_route_coordinator.dart';
import '../data/lesson_recording_history_store.dart';
import 'lesson_recording_storage.dart';

class LessonRecording {
  const LessonRecording({required this.filePath, required this.duration});

  final String filePath;
  final Duration duration;
}

/// Selects the physical output used for one lesson clip.
///
/// Guided lesson playback normally stays on [selectedLessonDevice] for the
/// whole prompt/sample/capture turn. [phoneSpeaker] remains available only for
/// callers that explicitly need to leave the selected lesson route.
enum LessonPlaybackRoute { selectedLessonDevice, phoneSpeaker }

class LessonMediaService {
  LessonMediaService({
    AudioRecorder? recorder,
    AudioPlaybackService? playbackService,
    HfpAudioControl? hfpAudioControl,
    AudioTurnCoordinator? audioTurnCoordinator,
    AudioTurnOwner audioTurnOwner = AudioTurnOwner.listeningLesson,
    LessonRecordingHistoryStore? historyStore,
  }) : _recorder = recorder,
       _playbackService = playbackService,
       _hfpAudioControl = hfpAudioControl,
       _audioTurnCoordinator = audioTurnCoordinator,
       _audioTurnOwner = audioTurnOwner,
       historyStore = historyStore ?? const LessonRecordingHistoryStore() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _hfpStatusSubscription = _hfpAudioControl?.statusChanges.listen((status) {
        if (_activeHfpRouteToken == null ||
            status.routeActive ||
            status.phase == BluetoothAudioConnectionPhase.connecting ||
            status.phase == BluetoothAudioConnectionPhase.discovering) {
          return;
        }
        _playbackRequestGeneration += 1;
        final completion = _activePlaybackCompletion;
        if (completion != null && !completion.isCompleted) {
          completion.completeError(
            const HfpAudioException(
              'Kết nối âm thanh H20 bị gián đoạn. Bạn bấm nghe lại nhé.',
            ),
          );
        }
        // Stop the current clip before Android can continue it on the phone.
        unawaited(_playbackService?.stop().catchError((Object _) {}));
        if (_recordingStartedAt != null) {
          const failure = LessonMediaException(
            'Mic H20 bị ngắt kết nối khi đang ghi âm. Bạn kết nối lại H20 rồi ghi lại nhé.',
          );
          final context = _activeContext;
          if (context != null) {
            unawaited(_cancelRecordingAfterRouteLoss(failure, context));
          }
        }
      });
    }
  }

  final LessonRecordingHistoryStore historyStore;

  AudioRecorder? _recorder;
  AudioPlaybackService? _playbackService;
  final HfpAudioControl? _hfpAudioControl;
  final AudioTurnCoordinator? _audioTurnCoordinator;
  final AudioTurnOwner _audioTurnOwner;
  DateTime? _recordingStartedAt;
  String? _activePath;
  _ActiveLessonRecording? _activeContext;
  Completer<void>? _activePlaybackCompletion;
  Future<void> _recordingOperation = Future<void>.value();
  Object? _activeHfpRouteToken;
  StreamSubscription<BluetoothAudioStatus>? _hfpStatusSubscription;
  int _playbackRequestGeneration = 0;
  int _recordingRequestGeneration = 0;
  LessonMediaException? _recordingRouteFailure;
  final StreamController<LessonMediaException> _recordingErrors =
      StreamController<LessonMediaException>.broadcast();

  /// Unexpected capture failures that must also clear a screen's recording UI.
  Stream<LessonMediaException> get recordingErrors => _recordingErrors.stream;

  AudioRecorder get _activeRecorder => _recorder ??= AudioRecorder();

  /// Local volume samples for endpoint detection while a lesson is recording.
  /// Observing this stream does not start another recorder or change the
  /// selected phone/HFP input.
  Stream<double> get recordingAmplitudeDbfs {
    // Test doubles and callers that do not own an active recorder should not
    // start the record plugin's periodic amplitude monitor.
    if (_recordingStartedAt == null) return const Stream<double>.empty();
    return _activeRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 90))
        .map((amplitude) => amplitude.current);
  }

  AudioPlaybackService get _activePlayback =>
      _playbackService ??= JustAudioPlaybackService(
        audioTurnCoordinator: _audioTurnCoordinator,
        audioTurnOwner: _audioTurnOwner,
      );

  bool get _shouldUseSelectedHfp =>
      shouldUseSelectedLessonHfp(_hfpAudioControl?.status);

  Future<String> recordingPath({
    required String lessonId,
    required int sentenceNumber,
    String? extension,
  }) =>
      createLessonRecordingPath(lessonId, sentenceNumber, extension: extension);

  Future<String?> existingRecording({
    required String lessonId,
    required int sentenceNumber,
    String? sentenceId,
  }) async {
    try {
      final entries = await historyStore.readForSentence(
        lessonId,
        sentenceId ?? '$lessonId-sentence-$sentenceNumber',
      );
      for (final entry in entries) {
        final path = await findLessonRecording(entry.filePath);
        if (path != null) {
          return path;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> play(
    Uri uri, {
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = androidSpeechBoostDb,
    bool fixedPlaybackGain = false,
  }) async {
    final generation = ++_playbackRequestGeneration;
    await _preparePlaybackRoute(route);
    _requireCurrentPlayback(generation);
    // Route/session preparation can rebuild Android's playback chain. Apply
    // gain afterwards so every clip starts with the requested level.
    await _setPlaybackGain(playbackGainDb, fixed: fixedPlaybackGain);
    _requireCurrentPlayback(generation);
    await _activePlayback.play(uri);
  }

  void _requireCurrentPlayback(int generation) {
    if (generation != _playbackRequestGeneration) {
      throw const LessonMediaException('Lượt phát âm thanh đã dừng.');
    }
  }

  Future<void> _setPlaybackGain(double gainDb, {required bool fixed}) async {
    final playback = _activePlayback;
    if (fixed && playback is FixedPlaybackGainAwareAudioPlaybackService) {
      await (playback as FixedPlaybackGainAwareAudioPlaybackService)
          .setFixedPlaybackGainDb(gainDb);
      return;
    }
    if (playback is PlaybackGainAwareAudioPlaybackService) {
      await (playback as PlaybackGainAwareAudioPlaybackService)
          .setPlaybackGainDb(gainDb);
    }
  }

  Stream<bool> get playbackPlayingStream => _activePlayback.playingStream;

  Stream<Duration> get playbackPositionStream {
    final playback = _activePlayback;
    return playback is ProgressAwareAudioPlaybackService
        ? (playback as ProgressAwareAudioPlaybackService).positionStream
        : const Stream<Duration>.empty();
  }

  Stream<Duration?> get playbackDurationStream {
    final playback = _activePlayback;
    return playback is ProgressAwareAudioPlaybackService
        ? (playback as ProgressAwareAudioPlaybackService).durationStream
        : const Stream<Duration?>.empty();
  }

  Duration get playbackPosition {
    final playback = _activePlayback;
    return playback is ProgressAwareAudioPlaybackService
        ? (playback as ProgressAwareAudioPlaybackService).position
        : Duration.zero;
  }

  Duration? get playbackDuration {
    final playback = _activePlayback;
    return playback is ProgressAwareAudioPlaybackService
        ? (playback as ProgressAwareAudioPlaybackService).duration
        : null;
  }

  /// Rewinds the currently loaded long-form source without replacing it.
  /// Song flows use this for the explicit "nghe lại" command; ordinary lesson
  /// prompts continue to use their existing source lifecycle.
  Future<bool> rewindPlayback() async {
    final playback = _activePlayback;
    if (playback is! SeekableAudioPlaybackService) return false;
    await (playback as SeekableAudioPlaybackService).seek(Duration.zero);
    return true;
  }

  Future<void> preload(Uri uri) => _activePlayback.preload(uri);

  Future<void> unlockPlaybackForUserGesture() async {
    final playback = _activePlayback;
    if (playback is UserGestureAudioPlaybackService) {
      await (playback as UserGestureAudioPlaybackService)
          .unlockForUserGesture();
    }
  }

  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = androidSpeechBoostDb,
    bool fixedPlaybackGain = false,
  }) async {
    final generation = ++_playbackRequestGeneration;
    final playback = _activePlayback;
    await _preparePlaybackRoute(route);
    _requireCurrentPlayback(generation);
    // Keep authored clips, prompts, and child replays deterministic even after
    // Android switches between media and HFP communication attributes.
    await _setPlaybackGain(playbackGainDb, fixed: fixedPlaybackGain);
    _requireCurrentPlayback(generation);
    final completed = Completer<void>();
    // A native route-loss event can arrive while play() is still starting.
    // Observe errors immediately; the awaited future below still propagates
    // them to the guided sequence instead of reporting successful playback.
    completed.future.ignore();
    final previousCompletion = _activePlaybackCompletion;
    if (previousCompletion != null && !previousCompletion.isCompleted) {
      previousCompletion.complete();
    }
    _activePlaybackCompletion = completed;
    var started = false;
    final CompletionAwareAudioPlaybackService? completionPlayback =
        playback is CompletionAwareAudioPlaybackService
        ? playback as CompletionAwareAudioPlaybackService
        : null;
    final subscription = playback.playingStream.listen(
      (playing) {
        if (playing) {
          started = true;
        } else if (completionPlayback == null &&
            started &&
            !completed.isCompleted) {
          completed.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completed.isCompleted) {
          completed.completeError(error, stackTrace);
        }
      },
    );
    StreamSubscription<void>? completionSubscription;
    try {
      await playback.play(uri);
      started = true;
      // Subscribe only after this source has actually started. just_audio's
      // state stream can replay ProcessingState.completed from the previous
      // source when a listener is attached, which must not finish the new
      // lesson intro early.
      completionSubscription = completionPlayback?.completionStream.listen(
        (_) {
          if (!completed.isCompleted) {
            completed.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completed.isCompleted) {
            completed.completeError(error, stackTrace);
          }
        },
      );
      await completed.future.timeout(timeout);
    } finally {
      await Future.wait<void>(<Future<void>>[
        subscription.cancel(),
        if (completionSubscription != null) completionSubscription.cancel(),
      ]);
      if (identical(_activePlaybackCompletion, completed)) {
        _activePlaybackCompletion = null;
      }
    }
  }

  Future<void> stopPlayback() async {
    _playbackRequestGeneration += 1;
    // A playback-only stop must not switch a live Android microphone away
    // from H20. During navigation, cancelRecording releases the route after
    // the recorder has restored its own AudioManager state.
    final androidCaptureActive =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        _recordingStartedAt != null;
    await _stopPlayback(releaseAudioRoute: !androidCaptureActive);
  }

  /// Explicitly leaves a lesson-owned HFP route and prepares phone output.
  Future<void> preparePhoneSpeakerOutput() =>
      _preparePlaybackRoute(LessonPlaybackRoute.phoneSpeaker);

  /// Prepares and verifies the selected H20 output before native TTS supplies
  /// lesson guidance. When H20 is selected this is deliberately fail-closed:
  /// a route negotiation error must stay visible to the caller instead of
  /// silently moving child-facing speech to the phone speaker.
  Future<void> prepareSelectedLessonOutput() =>
      _preparePlaybackRoute(LessonPlaybackRoute.selectedLessonDevice);

  /// Transfers the live HFP lease to Apple Speech after its native audio engine
  /// has started successfully. The native recognizer now owns and will release
  /// the same route, so this service must not retain a stale ownership flag.
  void handoffSelectedLessonOutputToNativeCapture() {
    final control = _hfpAudioControl;
    final leaseControl = control is HfpAudioRouteLeaseControl
        ? control as HfpAudioRouteLeaseControl
        : null;
    if (leaseControl != null) {
      unawaited(leaseControl.handoffAudioRoute());
    }
    _activeHfpRouteToken = null;
  }

  Future<void> _stopPlayback({required bool releaseAudioRoute}) async {
    final completion = _activePlaybackCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
    await _playbackService?.stop();
    if (releaseAudioRoute) {
      await _releaseHfpRoute();
    }
  }

  Future<void> startRecording({
    required String lessonId,
    required int sentenceNumber,
    String? lessonTitle,
    String? sentenceId,
    String? english,
    String? vietnamese,
    bool saveToHistory = true,
  }) {
    final generation = ++_recordingRequestGeneration;
    return _serializeRecordingOperation(() async {
      var recorderStarted = false;
      try {
        _recordingRouteFailure = null;
        // Keep an already confirmed HFP route alive while switching from the final
        // guide clip to capture. Releasing it here makes iOS renegotiate to the
        // phone between "Con nói lại nhé" and AVAudioRecorder opening its input.
        await _stopPlayback(releaseAudioRoute: false);
        _requireCurrentRecording(generation);
        final recorder = _activeRecorder;
        if (!await recorder.hasPermission()) {
          throw const LessonMediaException(
            'Ứng dụng cần quyền micro để lưu bản ghi của bạn.',
          );
        }
        _requireCurrentRecording(generation);

        var useSelectedHfp = _shouldUseSelectedHfp;
        final session = await AudioSession.instance;
        await session.configure(
          lessonRecordingAudioSessionConfiguration(
            useSelectedHfp: useSelectedHfp,
          ),
        );
        _requireCurrentRecording(generation);

        if (useSelectedHfp) {
          // On iOS, the Dart ownership flag is not proof that AVAudioSession still
          // exposes the selected HFP input. Revalidate the native route at the
          // exact playback-to-capture boundary before resolving recorder inputs.
          try {
            await _activateSelectedHfpRoute(
              force: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
            );
            _requireCurrentRecording(generation);
          } catch (_) {
            _requireCurrentRecording(generation);
            await _releaseHfpRoute();
            useSelectedHfp = false;
            await session.configure(
              lessonRecordingAudioSessionConfiguration(useSelectedHfp: false),
            );
            _requireCurrentRecording(generation);
          }
        } else {
          await _releaseHfpRoute();
          _requireCurrentRecording(generation);
        }

        final recordingInput = await _resolveRecordingInput(
          recorder,
          useSelectedHfp: useSelectedHfp,
        );
        _requireCurrentRecording(generation);

        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          // AudioSession/HfpAudioControl already selected and verified the input.
          // Letting record_ios configure AVAudioSession again at recorder.start()
          // can replace the confirmed H20 route and produce a silent M4A even
          // though the UI still reports HFP as active. Restore plugin ownership
          // for phone-mic recordings, where there is no HFP route owner.
          await recorder.ios?.manageAudioSession(!useSelectedHfp);
          _requireCurrentRecording(generation);
        }

        final path = await recordingPath(
          lessonId: lessonId,
          sentenceNumber: sentenceNumber,
        );
        _requireCurrentRecording(generation);
        await recorder.start(
          lessonRecordConfig(
            useSelectedHfp: useSelectedHfp,
            inputDevice: recordingInput,
          ),
          path: path,
        );
        recorderStarted = true;
        _requireCurrentRecording(generation);
        if (useSelectedHfp && _hfpAudioControl?.status.routeActive != true) {
          throw const LessonMediaException(
            'Mic H20 bị ngắt kết nối khi mở ghi âm. Bạn kết nối lại H20 rồi thử lại nhé.',
          );
        }
        _activePath = path;
        _activeContext = _ActiveLessonRecording(
          lessonId: lessonId,
          lessonTitle: lessonTitle ?? lessonId,
          sentenceId: sentenceId ?? '$lessonId-sentence-$sentenceNumber',
          sentenceNumber: sentenceNumber,
          english: english ?? '',
          vietnamese: vietnamese ?? '',
          saveToHistory: saveToHistory,
        );
        _recordingStartedAt = DateTime.now();
      } catch (_) {
        if (recorderStarted) {
          await _recorder?.cancel().catchError((Object _) {});
        }
        await _releaseHfpRoute();
        rethrow;
      }
    });
  }

  void _requireCurrentRecording(int generation) {
    if (generation != _recordingRequestGeneration) {
      throw const LessonMediaException('Lượt ghi âm đã dừng.');
    }
  }

  Future<InputDevice?> _resolveRecordingInput(
    AudioRecorder recorder, {
    required bool useSelectedHfp,
  }) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return null;
    }
    final devices = await recorder.listInputDevices();
    // Android's default-input probe can select the built-in stereo mic even
    // while communication audio is routed to H20. Pinning this device also
    // makes record_android inspect the selected input's actual capabilities.
    final selected = selectLessonRecordingInput(
      devices,
      useSelectedHfp: useSelectedHfp,
      selectedHfpDeviceId: _hfpAudioControl?.status.deviceId,
      selectedHfpDeviceName: _hfpAudioControl?.status.deviceName,
    );
    if (selected != null) {
      return selected;
    }
    if (useSelectedHfp) {
      throw const LessonMediaException(
        'Chưa mở được mic H20 đã chọn. Hãy kết nối lại H20 rồi thử lại.',
      );
    }
    throw const LessonMediaException(
      'Chưa tìm thấy micro tích hợp của điện thoại.',
    );
  }

  Future<void> _preparePlaybackRoute(LessonPlaybackRoute route) async {
    final playback = _activePlayback;
    final selectedHfp =
        route == LessonPlaybackRoute.selectedLessonDevice &&
        _shouldUseSelectedHfp;
    // Keep both the lesson audio and assistant speech on the H20 selected for
    // the lesson. Relying on iOS to pick an A2DP route is unreliable for H20:
    // when its media profile is not active, iOS silently falls back to the
    // phone speaker. Holding the selected HFP/SCO route prevents that split
    // until the lesson explicitly releases the route.
    final useSelectedHfp = selectedHfp;
    if (playback is CommunicationRouteAwareAudioPlaybackService) {
      (playback as CommunicationRouteAwareAudioPlaybackService)
          .setCommunicationRouteActive(useSelectedHfp);
    }
    if (!useSelectedHfp) {
      // Clear SCO before configuring ordinary playback. This prevents a coach
      // prompt from inheriting the preceding H20 communication route.
      await _releaseHfpRoute(immediately: true);
      await playback.prepare();
      return;
    }
    // Configure playAndRecord/voiceChat first, then re-assert the selected HFP
    // input. This order prevents just_audio's playback preparation from
    // replacing the route selected by the native H20 bridge.
    await playback.prepare();
    await _activateSelectedHfpRoute(
      force: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    );
  }

  Future<void> _activateSelectedHfpRoute({bool force = false}) async {
    final control = _hfpAudioControl;
    // A Bluetooth audio-state broadcast can report that SCO dropped while the
    // Dart lease is still valid. Re-open the selected H20 in that case instead
    // of trusting a stale ownership token and playing on a different stream.
    if (_activeHfpRouteToken != null &&
        !force &&
        control?.status.routeActive == true) {
      return;
    }
    if (control == null) {
      return;
    }
    await control.startAudioRoute();
    final leaseControl = control is HfpAudioRouteLeaseControl
        ? control as HfpAudioRouteLeaseControl
        : null;
    _activeHfpRouteToken = leaseControl != null
        ? leaseControl.activeAudioRouteToken
        : Object();
  }

  Future<void> _releaseHfpRoute({bool immediately = false}) async {
    // A start may still be awaiting native confirmation and have no token yet.
    // Scoped controls serialize stop behind it and invalidate that late start.
    if (_activeHfpRouteToken == null &&
        _hfpAudioControl is! HfpAudioRouteLeaseControl) {
      return;
    }
    _activeHfpRouteToken = null;
    final control = _hfpAudioControl;
    if (immediately && control is HfpImmediateRouteReleaseControl) {
      await (control as HfpImmediateRouteReleaseControl)
          .stopAudioRouteImmediately();
    } else {
      await control?.stopAudioRoute();
    }
  }

  @visibleForTesting
  static RecordConfig lessonRecordConfig({
    required bool useSelectedHfp,
    InputDevice? inputDevice,
  }) => RecordConfig(
    encoder: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? AudioEncoder.wav
        : AudioEncoder.aacLc,
    sampleRate: 16000,
    bitRate: 64000,
    numChannels: 1,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
    device: inputDevice,
    // HfpAudioControl already owns the exact selected H20 route. Letting the
    // record plugin manage Bluetooth too makes it select the first SCO device
    // and clear that route on stop.
    androidConfig: AndroidRecordConfig(
      manageBluetooth: false,
      audioSource: useSelectedHfp
          ? AndroidAudioSource.voiceCommunication
          : AndroidAudioSource.mic,
      // record_android treats modeNormal as "do not manage AudioManager mode".
      // Its recorder remembers the mode from its first capture and would restore
      // that stale mode on stop, overriding a later HFP route owned by the bridge.
      audioManagerMode: AudioManagerMode.modeNormal,
    ),
    iosConfig: IosRecordConfig(
      categoryOptions: useSelectedHfp
          ? const <IosAudioCategoryOption>[
              IosAudioCategoryOption.allowBluetooth,
            ]
          : const <IosAudioCategoryOption>[
              IosAudioCategoryOption.defaultToSpeaker,
            ],
    ),
  );

  Future<LessonRecording> stopRecording() {
    _recordingRequestGeneration += 1;
    return _serializeRecordingOperation(() async {
      try {
        final routeFailure = _recordingRouteFailure;
        if (routeFailure != null) throw routeFailure;
        final recorder = _recorder;
        final startedAt = _recordingStartedAt;
        final expectedPath = _activePath;
        final context = _activeContext;
        if (recorder == null ||
            startedAt == null ||
            expectedPath == null ||
            context == null) {
          throw const LessonMediaException('Chưa có bản ghi đang thực hiện.');
        }
        // Capture the audible end before the plugin finalizes and flushes the
        // file. On slower Android devices that finalization can take about a
        // second; including it made a six-second recording appear as seven.
        final stoppedAt = DateTime.now();
        final recordedPath = await recorder.stop();
        _recordingStartedAt = null;
        _activePath = null;
        _activeContext = null;
        final resolvedPath = await resolveLessonRecording(
          recordedPath,
          expectedPath,
        );
        if (resolvedPath == null) {
          throw const LessonMediaException('Không tìm thấy bản ghi vừa tạo.');
        }
        final recording = LessonRecording(
          filePath: resolvedPath,
          duration: stoppedAt.difference(startedAt),
        );
        if (context.saveToHistory) {
          final createdAt = DateTime.now();
          final evictedPaths = await historyStore.addSuccessful(
            LessonRecordingHistoryEntry(
              id: '${context.sentenceId}-${createdAt.microsecondsSinceEpoch}',
              lessonId: context.lessonId,
              lessonTitle: context.lessonTitle,
              sentenceId: context.sentenceId,
              sentenceNumber: context.sentenceNumber,
              english: context.english,
              vietnamese: context.vietnamese,
              filePath: resolvedPath,
              duration: recording.duration,
              createdAt: createdAt,
            ),
          );
          for (final path in evictedPaths) {
            await deleteLessonRecording(path);
          }
        }
        // Keep the lesson's selected output through scoring and feedback.
        // Dropping SCO here starts a teardown that can arrive while the next
        // prompt is playing and switch that prompt back to the phone. Keep
        // the existing lifecycle on the other platforms.
        if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
          await _releaseHfpRoute();
        }
        return recording;
      } catch (_) {
        await _releaseHfpRoute();
        rethrow;
      }
    });
  }

  /// Adds audio captured by a native speech recognizer to the same local
  /// lesson history used by recordings produced through the record plugin.
  Future<LessonRecording> finalizeExternalRecording({
    required LessonRecording recording,
  }) async {
    final resolvedPath = await resolveLessonRecording(
      recording.filePath,
      recording.filePath,
    );
    if (resolvedPath == null) {
      throw const LessonMediaException('Không tìm thấy bản ghi vừa tạo.');
    }
    return LessonRecording(
      filePath: resolvedPath,
      duration: recording.duration,
    );
  }

  Future<LessonRecording> registerExternalRecording({
    required LessonRecording recording,
    required String lessonId,
    required String lessonTitle,
    required String sentenceId,
    required int sentenceNumber,
    required String english,
    required String vietnamese,
  }) async {
    final finalizedRecording = await finalizeExternalRecording(
      recording: recording,
    );
    final createdAt = DateTime.now();
    final evictedPaths = await historyStore.addSuccessful(
      LessonRecordingHistoryEntry(
        id: '$sentenceId-${createdAt.microsecondsSinceEpoch}',
        lessonId: lessonId,
        lessonTitle: lessonTitle,
        sentenceId: sentenceId,
        sentenceNumber: sentenceNumber,
        english: english,
        vietnamese: vietnamese,
        filePath: finalizedRecording.filePath,
        duration: finalizedRecording.duration,
        createdAt: createdAt,
      ),
    );
    for (final path in evictedPaths) {
      await deleteLessonRecording(path);
    }
    return finalizedRecording;
  }

  Future<void> cancelRecording() {
    _recordingRequestGeneration += 1;
    return _serializeRecordingOperation(() async {
      _recordingRouteFailure = null;
      try {
        await _recorder?.cancel();
        _recordingStartedAt = null;
        _activePath = null;
        _activeContext = null;
      } finally {
        await _releaseHfpRoute();
      }
    });
  }

  Future<void> _cancelRecordingAfterRouteLoss(
    LessonMediaException failure,
    _ActiveLessonRecording context,
  ) => _serializeRecordingOperation(() async {
    // A navigation cancellation or a newer capture can overtake the queued
    // route-loss callback. Only the recording that lost its route may stop.
    if (_recordingStartedAt == null || !identical(_activeContext, context)) {
      return;
    }
    _recordingRouteFailure = failure;
    try {
      await _recorder?.cancel();
    } catch (_) {
      // The route is already unavailable; keep the original useful failure.
    } finally {
      _recordingStartedAt = null;
      _activePath = null;
      _activeContext = null;
      await _releaseHfpRoute().catchError((Object _) {});
      _recordingErrors.add(failure);
    }
  });

  Future<T> _serializeRecordingOperation<T>(Future<T> Function() action) {
    final operation = _recordingOperation.then<T>((_) => action());
    _recordingOperation = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> deleteRecording(String path) => deleteLessonRecording(path);

  Future<void> deleteRecordingsForLesson(String lessonId) async {
    final paths = await historyStore.removeLesson(lessonId);
    for (final path in paths) {
      await deleteLessonRecording(path);
    }
  }

  Future<void> dispose() async {
    _playbackRequestGeneration += 1;
    _recordingRequestGeneration += 1;
    await _hfpStatusSubscription?.cancel();
    await _recordingOperation;
    await _releaseHfpRoute();
    await _recorder?.dispose();
    await _playbackService?.dispose();
    await _recordingErrors.close();
  }
}

@visibleForTesting
bool shouldUseSelectedLessonHfp(BluetoothAudioStatus? status) =>
    status != null &&
    status.isBridgeSupported &&
    (status.deviceId != null || status.isConnected);

@visibleForTesting
AudioSessionConfiguration lessonRecordingAudioSessionConfiguration({
  required bool useSelectedHfp,
}) => AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
  avAudioSessionCategoryOptions: useSelectedHfp
      ? AVAudioSessionCategoryOptions.allowBluetooth
      : AVAudioSessionCategoryOptions.defaultToSpeaker,
  avAudioSessionMode: AVAudioSessionMode.voiceChat,
  androidAudioAttributes: const AndroidAudioAttributes(
    contentType: AndroidAudioContentType.speech,
    usage: AndroidAudioUsage.voiceCommunication,
  ),
  androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  androidWillPauseWhenDucked: true,
);

@visibleForTesting
InputDevice? selectLessonRecordingInput(
  List<InputDevice> devices, {
  required bool useSelectedHfp,
  String? selectedHfpDeviceId,
  String? selectedHfpDeviceName,
}) {
  if (!useSelectedHfp) {
    for (final device in devices) {
      if (device.type == InputDeviceType.builtIn) {
        return device;
      }
    }
    return null;
  }

  final selectedId = selectedHfpDeviceId?.trim();
  if (selectedId != null && selectedId.isNotEmpty) {
    for (final device in devices) {
      if (device.id == selectedId &&
          device.type == InputDeviceType.bluetoothSco) {
        return device;
      }
    }
  }

  final selectedName = selectedHfpDeviceName?.trim().toLowerCase();
  if (selectedName != null && selectedName.isNotEmpty) {
    for (final device in devices) {
      if (device.type == InputDeviceType.bluetoothSco &&
          device.label.trim().toLowerCase() == selectedName) {
        return device;
      }
    }
  }

  final hfpDevices = devices
      .where((device) => device.type == InputDeviceType.bluetoothSco)
      .toList(growable: false);
  return hfpDevices.length == 1 ? hfpDevices.single : null;
}

class _ActiveLessonRecording {
  const _ActiveLessonRecording({
    required this.lessonId,
    required this.lessonTitle,
    required this.sentenceId,
    required this.sentenceNumber,
    required this.english,
    required this.vietnamese,
    required this.saveToHistory,
  });

  final String lessonId;
  final String lessonTitle;
  final String sentenceId;
  final int sentenceNumber;
  final String english;
  final String vietnamese;
  final bool saveToHistory;
}

class LessonMediaException implements Exception {
  const LessonMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}
