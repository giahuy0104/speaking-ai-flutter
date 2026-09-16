import 'dart:async';

import '../../../core/audio/adaptive_voice_activity_detector.dart';

enum LessonRecordingEndpointReason { silence, maximumDuration }

/// Stops one listening-lesson recording after the child has finished speaking.
///
/// Audio stays local while this detector observes volume only. The completed
/// recording is still scored once, after the recorder has been stopped. A hard
/// maximum keeps the previous six-second answer window as a safety boundary.
class LessonRecordingEndpointDetector {
  LessonRecordingEndpointDetector({
    this.silenceDuration = const Duration(milliseconds: 700),
    this.maximumDuration = const Duration(seconds: 6),
    AdaptiveVoiceActivityDetector? voiceActivityDetector,
    DateTime Function()? now,
  }) : _voiceActivityDetector =
           voiceActivityDetector ??
           AdaptiveVoiceActivityDetector(
             calibrationDuration: const Duration(milliseconds: 150),
             minimumSpeechDuration: const Duration(milliseconds: 120),
             minimumSpeechVariationDb: 2,
             startMarginDb: 7,
             stopMarginDb: 4,
           ),
       _now = now ?? DateTime.now;

  final Duration silenceDuration;
  final Duration maximumDuration;
  final AdaptiveVoiceActivityDetector _voiceActivityDetector;
  final DateTime Function() _now;

  StreamSubscription<double>? _amplitudeSubscription;
  Timer? _silenceTimer;
  Timer? _maximumTimer;
  DateTime? _startedAt;
  void Function(LessonRecordingEndpointReason reason)? _onEndpoint;
  bool _speechDetected = false;
  bool _endpointSent = false;
  int _generation = 0;
  DateTime? _sustainedVoiceStartedAt;

  /// HFP AGC can flatten a short child's utterance enough that the adaptive
  /// detector sees almost no dB variation. A clearly elevated signal sustained
  /// for this window is still speech, while being well below the detector's
  /// steady-noise promotion window.
  static const Duration _flatSpeechConfirmation = Duration(milliseconds: 270);

  bool get speechDetected => _speechDetected;

  void start({
    required Stream<double>? amplitudeDbfs,
    required void Function(LessonRecordingEndpointReason reason) onEndpoint,
  }) {
    cancel();
    final generation = ++_generation;
    _voiceActivityDetector.reset();
    _startedAt = _now();
    _onEndpoint = onEndpoint;
    _speechDetected = false;
    _endpointSent = false;
    _sustainedVoiceStartedAt = null;

    if (amplitudeDbfs != null) {
      _amplitudeSubscription = amplitudeDbfs.listen(
        (dbfs) => _handleAmplitude(dbfs, generation),
        // A device that cannot report amplitude still uses the six-second cap.
        onError: (Object _) {},
      );
    }
    _maximumTimer = Timer(
      maximumDuration,
      () => _finish(generation, LessonRecordingEndpointReason.maximumDuration),
    );
  }

  void cancel() {
    _generation += 1;
    _endpointSent = true;
    _onEndpoint = null;
    _sustainedVoiceStartedAt = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _maximumTimer?.cancel();
    _maximumTimer = null;
    final subscription = _amplitudeSubscription;
    _amplitudeSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// A live ASR transcript is stronger evidence than the volume threshold.
  /// Refresh the quiet window for partial results even if RMS events stop.
  void confirmSpeech() {
    if (_endpointSent) return;
    _voiceActivityDetector.confirmSpeech();
    _speechDetected = true;
    _sustainedVoiceStartedAt = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _scheduleSilenceEndpoint(_generation);
  }

  void _handleAmplitude(double dbfs, int generation) {
    if (generation != _generation || _endpointSent) return;
    final startedAt = _startedAt;
    final activity = _voiceActivityDetector.addSample(
      dbfs,
      elapsed: startedAt == null ? Duration.zero : _now().difference(startedAt),
    );
    if (activity.speechStarted) _speechDetected = true;

    if (!_speechDetected && !activity.isCalibrating) {
      if (dbfs >= activity.startThresholdDbfs) {
        final elevatedAt = _sustainedVoiceStartedAt ??= _now();
        if (_now().difference(elevatedAt) >= _flatSpeechConfirmation) {
          _voiceActivityDetector.confirmSpeech();
          _speechDetected = true;
          _sustainedVoiceStartedAt = null;
        }
      } else {
        _sustainedVoiceStartedAt = null;
      }
    }

    if (activity.voiceActive ||
        (_speechDetected && dbfs >= activity.stopThresholdDbfs)) {
      _silenceTimer?.cancel();
      _silenceTimer = null;
      return;
    }
    if (!_speechDetected || activity.isCalibrating || _silenceTimer != null) {
      return;
    }
    _scheduleSilenceEndpoint(generation);
  }

  void _scheduleSilenceEndpoint(int generation) {
    _silenceTimer = Timer(
      silenceDuration,
      () => _finish(generation, LessonRecordingEndpointReason.silence),
    );
  }

  void _finish(int generation, LessonRecordingEndpointReason reason) {
    if (generation != _generation || _endpointSent) return;
    _endpointSent = true;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _maximumTimer?.cancel();
    _maximumTimer = null;
    final subscription = _amplitudeSubscription;
    _amplitudeSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final callback = _onEndpoint;
    _onEndpoint = null;
    _sustainedVoiceStartedAt = null;
    callback?.call(reason);
  }
}
