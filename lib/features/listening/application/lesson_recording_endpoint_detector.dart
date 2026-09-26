import 'dart:async';

import 'package:flutter/foundation.dart';

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
             // Quiet H20 recordings can peak below the shared VAD's -46 dBFS
             // floor. Keep ambient-relative margins without forcing those
             // utterances to wait for the entire six-second recording cap.
             minimumStartThresholdDbfs: _usesSensitiveMobileCapture ? -60 : -46,
             minimumStopThresholdDbfs: _usesSensitiveMobileCapture ? -64 : -50,
           ),
       _now = now ?? DateTime.now;

  final Duration silenceDuration;
  final Duration maximumDuration;
  final AdaptiveVoiceActivityDetector _voiceActivityDetector;
  final DateTime Function() _now;
  final bool _recoverQuietCapture = _usesSensitiveMobileCapture;

  static bool get _usesSensitiveMobileCapture =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  StreamSubscription<double>? _amplitudeSubscription;
  Timer? _silenceTimer;
  Timer? _maximumTimer;
  DateTime? _startedAt;
  void Function(LessonRecordingEndpointReason reason)? _onEndpoint;
  bool _speechDetected = false;
  bool _endpointSent = false;
  int _generation = 0;
  DateTime? _sustainedVoiceStartedAt;
  DateTime? _earlyVoiceStartedAt;
  double? _earlyVoiceMinimum;
  double? _earlyVoiceMaximum;
  int _earlyVoiceSamples = 0;
  bool _earlyVoiceFinished = false;

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
    _earlyVoiceStartedAt = null;
    _earlyVoiceMinimum = null;
    _earlyVoiceMaximum = null;
    _earlyVoiceSamples = 0;
    _earlyVoiceFinished = false;

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
    if (!dbfs.isFinite) return;
    final startedAt = _startedAt;
    final activity = _voiceActivityDetector.addSample(
      dbfs,
      elapsed: startedAt == null ? Duration.zero : _now().difference(startedAt),
    );
    if (activity.speechStarted) _speechDetected = true;
    if (_recoverQuietCapture && !_speechDetected) {
      _recoverSpeechDuringCalibration(dbfs);
    }

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

  /// A child can begin with the very first microphone samples. In that case
  /// calibration learns the child's voice as the ambient floor and never
  /// reports speech. Recover only a sustained opening burst followed by a
  /// clear level drop; a single impact or continuous fan noise does not qualify.
  void _recoverSpeechDuringCalibration(double dbfs) {
    if (_earlyVoiceFinished) return;
    final startedAt = _startedAt;
    if (startedAt == null) return;
    final now = _now();
    if (_earlyVoiceStartedAt == null) {
      if (now.difference(startedAt) > const Duration(milliseconds: 300)) {
        _earlyVoiceFinished = true;
        return;
      }
      if (dbfs < -60) return;
      _earlyVoiceStartedAt = now;
      _earlyVoiceMinimum = dbfs;
      _earlyVoiceMaximum = dbfs;
      _earlyVoiceSamples = 1;
      return;
    }

    final minimum = _earlyVoiceMinimum!;
    final maximum = _earlyVoiceMaximum!;
    if (dbfs <= minimum - 10) {
      _earlyVoiceFinished = true;
      final duration = now.difference(_earlyVoiceStartedAt!);
      final sustained =
          _earlyVoiceSamples >= 3 &&
          duration >= const Duration(milliseconds: 180);
      final speechLike =
          maximum - minimum >= 2 || duration >= _flatSpeechConfirmation;
      if (sustained && speechLike) {
        _voiceActivityDetector.confirmSpeech();
        _speechDetected = true;
      }
      return;
    }
    // Anchor the comparison to the opening calibration window. Following every
    // lower sample lets a gradually fading syllable drag the reference all the
    // way into silence, so the required 10 dB drop would never be observed.
    if (_earlyVoiceSamples < 3 && dbfs < minimum) {
      _earlyVoiceMinimum = dbfs;
    }
    if (dbfs > maximum) _earlyVoiceMaximum = dbfs;
    _earlyVoiceSamples += 1;
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
