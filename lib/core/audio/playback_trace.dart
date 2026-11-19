import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Always-on, low-volume trace of one native playback, printed to the device
/// log (`adb logcat | grep playback_trace`).
///
/// It answers "when did the stream end": the moment the buffered position
/// stops growing (download finished), the moment the position stops advancing
/// (sound ended), and whether just_audio ever reported `completed`. A streamed
/// WAV whose header carries an unknown length is the case it was added for.
///
/// Never logs transcripts, query strings (signed URLs carry text and a
/// signature) or audio bytes.
class PlaybackTraceRecorder {
  PlaybackTraceRecorder({
    required this.traceId,
    required this.source,
    DateTime Function()? now,
    this.maxSamples = defaultMaxSamples,
  }) : _now = now ?? DateTime.now,
       _startedAt = (now ?? DateTime.now)();

  /// 500 ms samples for 45 s: longer than the 30 s completion safety timeout.
  static const defaultMaxSamples = 90;

  final int traceId;
  final String source;
  final int maxSamples;
  final DateTime Function() _now;
  final DateTime _startedAt;

  String? _lastState;
  bool? _lastPlaying;
  int? _lastDurationMs;
  int _samples = 0;
  bool _finished = false;

  bool get isFinished => _finished;

  bool get samplesExhausted => _samples >= maxSamples;

  Map<String, Object?> _base(String event) => <String, Object?>{
    'event': event,
    'traceId': traceId,
    'source': source,
    'elapsedMs': _now().difference(_startedAt).inMilliseconds,
  };

  Map<String, Object?> started() => _base('playback_trace_started');

  /// A log record when the player state changed, or for a periodic [sample];
  /// null when there is nothing worth printing.
  Map<String, Object?>? observe({
    required String state,
    required bool playing,
    required Duration position,
    required Duration bufferedPosition,
    required Duration? duration,
    bool sample = false,
  }) {
    if (_finished) return null;
    final durationMs = duration?.inMilliseconds;
    final changed =
        state != _lastState ||
        playing != _lastPlaying ||
        durationMs != _lastDurationMs;
    if (!changed && !sample) return null;
    if (sample && !changed) {
      if (_samples >= maxSamples) return null;
      _samples++;
    }
    _lastState = state;
    _lastPlaying = playing;
    _lastDurationMs = durationMs;
    return <String, Object?>{
      ..._base(changed ? 'playback_trace_state' : 'playback_trace_sample'),
      'state': state,
      'playing': playing,
      'positionMs': position.inMilliseconds,
      'bufferedMs': bufferedPosition.inMilliseconds,
      'durationMs': durationMs,
    };
  }

  /// Final record; later calls return null.
  Map<String, Object?>? finish(String reason) {
    if (_finished) return null;
    _finished = true;
    return <String, Object?>{..._base('playback_trace_end'), 'reason': reason};
  }

  /// `https://host/api/audio/target?...` → `https://host/api/audio/target`.
  static String describe(Uri uri) {
    if (uri.isScheme('http') || uri.isScheme('https')) {
      return '${uri.scheme}://${uri.host}${uri.path}';
    }
    if (uri.isScheme('file')) {
      return 'file:${uri.pathSegments.lastOrNull ?? ''}';
    }
    return '${uri.scheme}:${uri.path}';
  }
}

/// Wires a [PlaybackTraceRecorder] to a just_audio [AudioPlayer].
class PlaybackTrace {
  PlaybackTrace._(this._recorder, this._log);

  static int _nextId = 0;

  final PlaybackTraceRecorder _recorder;
  final void Function(String line) _log;
  StreamSubscription<PlayerEvent>? _events;
  Timer? _ticker;

  static PlaybackTrace start(
    AudioPlayer player,
    Uri uri, {
    void Function(String line)? log,
  }) {
    final trace = PlaybackTrace._(
      PlaybackTraceRecorder(
        traceId: ++_nextId,
        source: PlaybackTraceRecorder.describe(uri),
      ),
      log ?? debugPrint,
    );
    trace._emit(trace._recorder.started());
    void record({required bool sample}) {
      // Diagnostics must never break playback (test doubles and future player
      // versions may not expose every getter).
      try {
        trace._emit(
          trace._recorder.observe(
            state: player.processingState.name,
            playing: player.playing,
            position: player.position,
            bufferedPosition: player.bufferedPosition,
            duration: player.duration,
            sample: sample,
          ),
        );
      } catch (_) {
        trace.end('trace_unavailable');
      }
    }

    trace._events = player.playerEventStream.listen(
      (_) => record(sample: false),
      onError: (Object error, StackTrace _) =>
          trace.end('error:${error.runtimeType}'),
    );
    trace._ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      record(sample: true);
      if (trace._recorder.samplesExhausted) trace.end('trace_limit');
    });
    return trace;
  }

  /// Prints the final record once and stops observing.
  void end(String reason) {
    _emit(_recorder.finish(reason));
    _dispose();
  }

  void _emit(Map<String, Object?>? record) {
    if (record != null) _log(jsonEncode(record));
  }

  void _dispose() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(_events?.cancel());
    _events = null;
  }
}
